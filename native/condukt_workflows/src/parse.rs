use std::collections::BTreeMap;

use serde_json::{Value as JsonValue, json};
use starlark::syntax::{AstModule, Dialect};

use crate::error::{WorkflowsError, WorkflowsResult};
use crate::terms::NifValue;

pub(crate) fn parse(filename: &str, source: String) -> WorkflowsResult<AstModule> {
    AstModule::parse(filename, source, &Dialect::Standard)
        .map_err(|error| WorkflowsError::Parse(error.to_string()))
}

pub(crate) fn parse_only(source: String, filename: String) -> WorkflowsResult<NifValue> {
    let ast = parse(&filename, source)?;
    let loads: Vec<NifValue> = ast
        .loads()
        .into_iter()
        .map(|load| NifValue::String(load.module_id.to_owned()))
        .collect();

    let mut map: BTreeMap<String, NifValue> = BTreeMap::new();
    map.insert("loads".to_owned(), NifValue::List(loads));
    Ok(NifValue::Map(map))
}

pub(crate) fn check(source: String, filename: String) -> WorkflowsResult<NifValue> {
    let _ast = parse(&filename, source)?;

    let report = json!({
        "ok": true,
        "diagnostics": [],
    });

    Ok(NifValue::from(report))
}

#[allow(dead_code)]
fn _round_trip_marker(value: JsonValue) -> NifValue {
    NifValue::from(value)
}
