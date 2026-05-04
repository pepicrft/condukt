use std::cell::RefCell;
use std::sync::Mutex;
use std::thread::{self, JoinHandle};

use crossbeam_channel::{Receiver, Sender, bounded};
use rustler::ResourceArc;
use serde_json::{Value as JsonValue, json};
use starlark::any::ProvidesStaticType;
use starlark::environment::{Globals, GlobalsBuilder, LibraryExtension, Module};
use starlark::eval::Evaluator;
use starlark::starlark_module;
use starlark::values::Value;
use starlark::values::none::NoneType;

use crate::error::{WorkflowsError, WorkflowsResult};
use crate::parse::parse;
use crate::value::{json_to_starlark, starlark_to_json};

#[derive(Debug)]
pub(crate) enum Event {
    Suspend(JsonValue),
    Done(JsonValue),
    Error(String),
}

pub(crate) struct RunHandle {
    inner: Mutex<RunInner>,
}

struct RunInner {
    request_rx: Option<Receiver<Event>>,
    response_tx: Option<Sender<JsonValue>>,
    join: Option<JoinHandle<()>>,
}

impl RunHandle {
    fn shutdown(&self) {
        if let Ok(mut inner) = self.inner.lock() {
            inner.request_rx.take();
            inner.response_tx.take();
            if let Some(join) = inner.join.take() {
                let _ = join.join();
            }
        }
    }
}

impl Drop for RunHandle {
    fn drop(&mut self) {
        self.shutdown();
    }
}

#[derive(ProvidesStaticType)]
struct HostBridge {
    request_tx: Sender<Event>,
    response_rx: Receiver<JsonValue>,
    workflow_declared: RefCell<bool>,
}

impl HostBridge {
    fn suspend(&self, request: JsonValue) -> WorkflowsResult<JsonValue> {
        self.request_tx
            .send(Event::Suspend(request))
            .map_err(|_| WorkflowsError::Cancelled)?;

        self.response_rx
            .recv()
            .map_err(|_| WorkflowsError::Cancelled)
    }
}

#[starlark_module]
fn workflow_globals(builder: &mut GlobalsBuilder) {
    fn run_cmd<'v>(
        argv: Value<'v>,
        cwd: Option<&str>,
        env: Option<Value<'v>>,
        eval: &mut Evaluator<'v, '_, '_>,
    ) -> anyhow::Result<Value<'v>> {
        let bridge = eval
            .extra
            .ok_or_else(|| anyhow::anyhow!("workflow runtime not initialised"))?
            .downcast_ref::<HostBridge>()
            .ok_or_else(|| anyhow::anyhow!("workflow runtime not initialised"))?;

        let argv_json =
            starlark_to_json(argv).map_err(|error| anyhow::anyhow!("run_cmd argv: {error}"))?;

        let env_json = match env {
            Some(value) => starlark_to_json(value)
                .map_err(|error| anyhow::anyhow!("run_cmd env: {error}"))?,
            None => JsonValue::Null,
        };

        let request = json!({
            "kind": "run_cmd",
            "argv": argv_json,
            "cwd": cwd,
            "env": env_json,
        });

        let response = bridge
            .suspend(request)
            .map_err(|error| anyhow::anyhow!("run_cmd suspend: {error}"))?;

        Ok(json_to_starlark(eval.heap(), response))
    }

    fn workflow<'v>(
        inputs: Option<Value<'v>>,
        eval: &mut Evaluator<'v, '_, '_>,
    ) -> anyhow::Result<NoneType> {
        let _ = inputs;

        let bridge = eval
            .extra
            .ok_or_else(|| anyhow::anyhow!("workflow runtime not initialised"))?
            .downcast_ref::<HostBridge>()
            .ok_or_else(|| anyhow::anyhow!("workflow runtime not initialised"))?;

        *bridge.workflow_declared.borrow_mut() = true;

        Ok(NoneType)
    }
}

fn build_globals() -> Globals {
    GlobalsBuilder::extended_by(&[LibraryExtension::StructType])
        .with(workflow_globals)
        .build()
}

fn run_workflow(
    source: String,
    filename: String,
    inputs: JsonValue,
    bridge: HostBridge,
) -> Result<JsonValue, String> {
    let globals = build_globals();
    let module = Module::new();
    let ast = parse(&filename, source).map_err(|error| error.to_string())?;

    let mut eval = Evaluator::new(&module);
    eval.extra = Some(&bridge);

    eval.eval_module(ast, &globals)
        .map_err(|error| error.to_string())?;

    if !*bridge.workflow_declared.borrow() {
        return Err("file does not call workflow(...) at top level".to_owned());
    }

    let run_value = module
        .get("run")
        .ok_or_else(|| "file does not define a top-level run(inputs) function".to_owned())?;

    let inputs_value = json_to_starlark(module.heap(), inputs);
    let result = eval
        .eval_function(run_value, &[inputs_value], &[])
        .map_err(|error| error.to_string())?;

    starlark_to_json(result).map_err(|error| error.to_string())
}

pub(crate) fn start_run(
    source: String,
    filename: String,
    inputs: JsonValue,
) -> WorkflowsResult<(ResourceArc<RunHandle>, Event)> {
    let (request_tx, request_rx) = bounded::<Event>(1);
    let (response_tx, response_rx) = bounded::<JsonValue>(1);

    let worker_request_tx = request_tx.clone();
    let join = thread::Builder::new()
        .name("condukt_workflow".to_owned())
        .spawn(move || {
            let bridge = HostBridge {
                request_tx: worker_request_tx,
                response_rx,
                workflow_declared: RefCell::new(false),
            };

            let request_tx = bridge.request_tx.clone();
            let event = match run_workflow(source, filename, inputs, bridge) {
                Ok(value) => Event::Done(value),
                Err(message) => Event::Error(message),
            };

            let _ = request_tx.send(event);
        })
        .map_err(|error| WorkflowsError::Runtime(format!("could not spawn worker: {error}")))?;

    drop(request_tx);

    let first = request_rx
        .recv()
        .map_err(|_| WorkflowsError::Runtime("worker terminated unexpectedly".to_owned()))?;

    let handle = RunHandle {
        inner: Mutex::new(RunInner {
            request_rx: Some(request_rx),
            response_tx: Some(response_tx),
            join: Some(join),
        }),
    };

    Ok((ResourceArc::new(handle), first))
}

pub(crate) fn resume_run(handle: &RunHandle, response: JsonValue) -> WorkflowsResult<Event> {
    let mut guard = handle
        .inner
        .lock()
        .map_err(|_| WorkflowsError::Runtime("run handle poisoned".to_owned()))?;

    {
        let response_tx = guard.response_tx.as_ref().ok_or_else(|| {
            WorkflowsError::Runtime("run handle already finished".to_owned())
        })?;

        response_tx.send(response).map_err(|_| {
            WorkflowsError::Runtime("worker no longer accepting responses".to_owned())
        })?;
    }

    let event = {
        let request_rx = guard.request_rx.as_ref().ok_or_else(|| {
            WorkflowsError::Runtime("run handle already finished".to_owned())
        })?;

        request_rx
            .recv()
            .map_err(|_| WorkflowsError::Runtime("worker terminated unexpectedly".to_owned()))?
    };

    if matches!(event, Event::Done(_) | Event::Error(_)) {
        guard.request_rx.take();
        guard.response_tx.take();
        if let Some(join) = guard.join.take() {
            let _ = join.join();
        }
    }

    Ok(event)
}

pub(crate) fn cancel_run(handle: &RunHandle) {
    handle.shutdown();
}
