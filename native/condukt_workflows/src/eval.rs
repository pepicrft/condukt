use std::cell::RefCell;
use std::collections::HashMap;

use serde_json::{Map as JsonMap, Value as JsonValue, json};
use starlark::any::ProvidesStaticType;
use starlark::environment::{FrozenModule, Globals, GlobalsBuilder, LibraryExtension, Module};
use starlark::eval::{Evaluator, ReturnFileLoader};
use starlark::starlark_module;
use starlark::syntax::{AstModule, Dialect};
use starlark::values::Value;
use starlark::values::none::NoneType;
use starlark_map::small_map::SmallMap;

use crate::errors::{WorkflowsError, WorkflowsResult};
use crate::terms::NifValue;

const MARKER_PREFIX: &str = "__condukt_json__:";
const PRELUDE: &str = r#"
condukt = struct(
    agent = agent,
    tool = tool,
    sandbox = struct(
        local = sandbox_local,
        virtual = sandbox_virtual,
    ),
    schedule = struct(
        cron = schedule_cron,
    ),
    trigger = struct(
        webhook = trigger_webhook,
    ),
    secret = secret,
    workflow = workflow,
)
"#;

#[derive(Debug, Default, ProvidesStaticType)]
struct WorkflowStore {
    workflows: RefCell<Vec<JsonValue>>,
}

impl WorkflowStore {
    fn push(&self, workflow: JsonValue) {
        self.workflows.borrow_mut().push(workflow);
    }

    fn graph(&self, loads: Vec<String>) -> NifValue {
        NifValue::from(json!({
            "loads": loads,
            "graph": {
                "workflows": self.workflows.borrow().clone(),
            },
        }))
    }
}

#[starlark_module]
fn condukt_builtins(builder: &mut GlobalsBuilder) {
    fn agent<'v>(
        model: Option<&str>,
        system_prompt: Option<&str>,
        tools: Option<Value<'v>>,
        thinking_level: Option<&str>,
        sandbox: Option<Value<'v>>,
    ) -> anyhow::Result<String> {
        Ok(marker(json!({
            "type": "agent",
            "model": model,
            "system_prompt": system_prompt,
            "tools": optional_value(tools, json!([]))?,
            "thinking_level": thinking_level,
            "sandbox": optional_value(sandbox, JsonValue::Null)?,
        })))
    }

    fn tool<'v>(
        #[starlark(require = pos)] reference: &str,
        #[starlark(kwargs)] opts: SmallMap<String, Value<'v>>,
    ) -> anyhow::Result<String> {
        let mut options = JsonMap::new();

        for (key, value) in opts {
            options.insert(key, starlark_value_to_json(value)?);
        }

        Ok(marker(json!({
            "type": "tool",
            "ref": reference,
            "opts": JsonValue::Object(options),
        })))
    }

    fn sandbox_local(cwd: Option<&str>) -> anyhow::Result<String> {
        Ok(marker(json!({
            "type": "sandbox",
            "kind": "local",
            "cwd": cwd,
        })))
    }

    fn sandbox_virtual<'v>(mounts: Option<Value<'v>>) -> anyhow::Result<String> {
        Ok(marker(json!({
            "type": "sandbox",
            "kind": "virtual",
            "mounts": optional_value(mounts, json!([]))?,
        })))
    }

    fn schedule_cron(expr: &str) -> anyhow::Result<String> {
        Ok(marker(json!({
            "type": "trigger",
            "kind": "cron",
            "expr": expr,
        })))
    }

    fn trigger_webhook(path: &str) -> anyhow::Result<String> {
        Ok(marker(json!({
            "type": "trigger",
            "kind": "webhook",
            "path": path,
        })))
    }

    fn secret(name: &str) -> anyhow::Result<String> {
        Ok(marker(json!({
            "type": "secret",
            "name": name,
        })))
    }

    fn workflow<'v>(
        name: &str,
        agent: Value<'v>,
        triggers: Option<Value<'v>>,
        inputs: Option<Value<'v>>,
        system_prompt: Option<&str>,
        model: Option<&str>,
        eval: &mut Evaluator<'v, '_, '_>,
    ) -> anyhow::Result<NoneType> {
        let workflow = json!({
            "name": name,
            "agent": starlark_value_to_json(agent)?,
            "triggers": optional_value(triggers, json!([]))?,
            "inputs_schema": optional_value(inputs, JsonValue::Null)?,
            "system_prompt": system_prompt,
            "model": model,
        });

        eval.extra
            .unwrap()
            .downcast_ref::<WorkflowStore>()
            .unwrap()
            .push(workflow);

        Ok(NoneType)
    }
}

pub(crate) fn eval(
    source: String,
    filename: String,
    globals: rustler::Term<'_>,
) -> WorkflowsResult<NifValue> {
    let loads = decode_loads(globals)?;
    eval_sources(source, filename, loads)
}

pub(crate) fn parse_only(source: String, filename: String) -> WorkflowsResult<NifValue> {
    let ast = parse(&filename, source)?;
    Ok(loads_value(&ast))
}

pub(crate) fn eval_sources(
    source: String,
    filename: String,
    loads: HashMap<String, String>,
) -> WorkflowsResult<NifValue> {
    let globals = workflow_globals();
    let ast = parse(&filename, source)?;
    let load_ids = load_ids(&ast);
    let frozen_loads = freeze_loads(&ast, &loads, &globals)?;
    let module = Module::new();
    let store = WorkflowStore::default();

    {
        let modules = frozen_loads
            .iter()
            .map(|(name, module)| (name.as_str(), module))
            .collect();
        let mut loader = ReturnFileLoader { modules: &modules };
        let mut eval = Evaluator::new(&module);

        eval.extra = Some(&store);
        eval.set_loader(&mut loader);
        eval_prelude(&mut eval, &globals)?;
        eval.eval_module(ast, &globals)
            .map_err(|error| WorkflowsError::Eval(error.to_string()))?;
    }

    Ok(store.graph(load_ids))
}

fn workflow_globals() -> Globals {
    GlobalsBuilder::extended_by(&[LibraryExtension::StructType])
        .with(condukt_builtins)
        .build()
}

fn decode_loads(globals: rustler::Term<'_>) -> WorkflowsResult<HashMap<String, String>> {
    let decoded: HashMap<String, HashMap<String, String>> = globals
        .decode()
        .map_err(|error| WorkflowsError::Eval(format!("invalid globals: {error:?}")))?;

    Ok(decoded.get("__loads__").cloned().unwrap_or_default())
}

fn parse(filename: &str, source: String) -> WorkflowsResult<AstModule> {
    AstModule::parse(filename, source, &Dialect::Standard)
        .map_err(|error| WorkflowsError::Parse(error.to_string()))
}

fn eval_prelude(eval: &mut Evaluator, globals: &Globals) -> WorkflowsResult<()> {
    let ast = parse("<condukt_prelude>", PRELUDE.to_owned())?;
    eval.eval_module(ast, globals)
        .map(|_| ())
        .map_err(|error| WorkflowsError::Eval(error.to_string()))
}

fn freeze_loads(
    ast: &AstModule,
    loads: &HashMap<String, String>,
    globals: &Globals,
) -> WorkflowsResult<Vec<(String, FrozenModule)>> {
    let mut modules = Vec::new();

    for load in ast.loads() {
        let module_id = load.module_id.to_owned();
        let source = loads
            .get(load.module_id)
            .ok_or_else(|| WorkflowsError::MissingLoad(load.module_id.to_owned()))?
            .to_owned();
        let frozen = freeze_module(module_id.clone(), source, loads, globals)?;
        modules.push((module_id, frozen));
    }

    Ok(modules)
}

fn freeze_module(
    filename: String,
    source: String,
    loads: &HashMap<String, String>,
    globals: &Globals,
) -> WorkflowsResult<FrozenModule> {
    let ast = parse(&filename, source)?;
    let frozen_loads = freeze_loads(&ast, loads, globals)?;
    let module = Module::new();
    let store = WorkflowStore::default();

    {
        let modules = frozen_loads
            .iter()
            .map(|(name, module)| (name.as_str(), module))
            .collect();
        let mut loader = ReturnFileLoader { modules: &modules };
        let mut eval = Evaluator::new(&module);

        eval.extra = Some(&store);
        eval.set_loader(&mut loader);
        eval_prelude(&mut eval, globals)?;
        eval.eval_module(ast, globals)
            .map_err(|error| WorkflowsError::Eval(error.to_string()))?;
    }

    module
        .freeze()
        .map_err(|error| WorkflowsError::Eval(format!("{error:?}")))
}

fn load_ids(ast: &AstModule) -> Vec<String> {
    ast.loads()
        .into_iter()
        .map(|load| load.module_id.to_owned())
        .collect()
}

fn loads_value(ast: &AstModule) -> NifValue {
    let loads = load_ids(ast);
    NifValue::from(json!({ "loads": loads }))
}

fn marker(value: JsonValue) -> String {
    format!("{MARKER_PREFIX}{value}")
}

fn optional_value(value: Option<Value<'_>>, default: JsonValue) -> anyhow::Result<JsonValue> {
    match value {
        Some(value) => starlark_value_to_json(value),
        None => Ok(default),
    }
}

fn starlark_value_to_json(value: Value<'_>) -> anyhow::Result<JsonValue> {
    if value.is_none() {
        return Ok(JsonValue::Null);
    }

    let json = value.to_json()?;
    let parsed = serde_json::from_str(&json)?;
    expand_markers(parsed)
}

fn expand_markers(value: JsonValue) -> anyhow::Result<JsonValue> {
    match value {
        JsonValue::String(value) if value.starts_with(MARKER_PREFIX) => {
            Ok(serde_json::from_str(&value[MARKER_PREFIX.len()..])?)
        }
        JsonValue::Array(values) => values
            .into_iter()
            .map(expand_markers)
            .collect::<anyhow::Result<Vec<_>>>()
            .map(JsonValue::Array),
        JsonValue::Object(values) => values
            .into_iter()
            .map(|(key, value)| Ok((key, expand_markers(value)?)))
            .collect::<anyhow::Result<JsonMap<String, JsonValue>>>()
            .map(JsonValue::Object),
        value => Ok(value),
    }
}

#[cfg(test)]
mod tests {
    use super::{eval_sources, parse_only};
    use crate::terms::NifValue;
    use std::collections::{BTreeMap, HashMap};

    #[test]
    fn evaluates_minimal_workflow_to_graph() {
        let source = r#"
condukt.workflow(
    name = "triage",
    agent = condukt.agent(
        model = "openai:gpt-4.1-mini",
        system_prompt = "Triage incoming issues.",
        tools = [condukt.tool("read")],
        sandbox = condukt.sandbox.local(cwd = "."),
    ),
    triggers = [condukt.trigger.webhook(path = "/triage")],
    inputs = {"type": "object"},
)
"#;

        let result =
            eval_sources(source.to_owned(), "triage.star".to_owned(), HashMap::new()).unwrap();
        let NifValue::Map(root) = result else {
            panic!("expected map");
        };
        let NifValue::Map(graph) = root.get("graph").unwrap() else {
            panic!("expected graph map");
        };
        let NifValue::List(workflows) = graph.get("workflows").unwrap() else {
            panic!("expected workflow list");
        };

        assert_eq!(workflows.len(), 1);
    }

    #[test]
    fn parse_errors_are_tagged() {
        let error = parse_only("def nope(:".to_owned(), "bad.star".to_owned()).unwrap_err();
        assert!(format!("{error}").contains("parse error"));
    }

    #[test]
    fn reports_loads_without_evaluating() {
        let result = parse_only(
            "load(\"./helpers.star\", \"helper\")".to_owned(),
            "main.star".to_owned(),
        )
        .unwrap();

        assert_eq!(
            result,
            NifValue::Map(BTreeMap::from([(
                "loads".to_owned(),
                NifValue::List(vec![NifValue::String("./helpers.star".to_owned())])
            )]))
        );
    }
}
