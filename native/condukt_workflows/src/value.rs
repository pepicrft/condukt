use serde_json::{Map as JsonMap, Value as JsonValue};
use starlark::values::dict::{AllocDict, DictRef};
use starlark::values::list::{AllocList, ListRef};
use starlark::values::tuple::TupleRef;
use starlark::values::{Heap, Value};

use crate::error::{WorkflowsError, WorkflowsResult};

pub(crate) fn starlark_to_json(value: Value<'_>) -> WorkflowsResult<JsonValue> {
    if value.is_none() {
        return Ok(JsonValue::Null);
    }

    if let Some(b) = value.unpack_bool() {
        return Ok(JsonValue::Bool(b));
    }

    if let Some(i) = value.unpack_i32() {
        return Ok(JsonValue::Number(serde_json::Number::from(i)));
    }

    if let Some(s) = value.unpack_str() {
        return Ok(JsonValue::String(s.to_owned()));
    }

    if let Some(list) = ListRef::from_value(value) {
        let entries = list
            .iter()
            .map(starlark_to_json)
            .collect::<WorkflowsResult<Vec<_>>>()?;
        return Ok(JsonValue::Array(entries));
    }

    if let Some(tuple) = TupleRef::from_value(value) {
        let entries = tuple
            .iter()
            .map(starlark_to_json)
            .collect::<WorkflowsResult<Vec<_>>>()?;
        return Ok(JsonValue::Array(entries));
    }

    if let Some(dict) = DictRef::from_value(value) {
        let mut entries = JsonMap::with_capacity(dict.len());
        for (key, value) in dict.iter() {
            let key = key.unpack_str().ok_or_else(|| {
                WorkflowsError::InvalidArguments("dict keys must be strings".into())
            })?;
            entries.insert(key.to_owned(), starlark_to_json(value)?);
        }
        return Ok(JsonValue::Object(entries));
    }

    if let Ok(json_string) = value.to_json() {
        if let Ok(parsed) = serde_json::from_str::<JsonValue>(&json_string) {
            return Ok(parsed);
        }
    }

    Err(WorkflowsError::InvalidArguments(format!(
        "cannot convert Starlark value of type {} to JSON",
        value.get_type()
    )))
}

pub(crate) fn json_to_starlark<'v>(heap: &'v Heap, value: JsonValue) -> Value<'v> {
    match value {
        JsonValue::Null => Value::new_none(),
        JsonValue::Bool(b) => Value::new_bool(b),
        JsonValue::Number(n) => {
            if let Some(i) = n.as_i64() {
                if let Ok(i) = i32::try_from(i) {
                    return heap.alloc(i);
                }
                return heap.alloc(i.to_string());
            }
            if let Some(f) = n.as_f64() {
                return heap.alloc(f);
            }
            heap.alloc(n.to_string())
        }
        JsonValue::String(s) => heap.alloc(s),
        JsonValue::Array(items) => {
            let values: Vec<Value> = items.into_iter().map(|v| json_to_starlark(heap, v)).collect();
            heap.alloc(AllocList(values))
        }
        JsonValue::Object(map) => {
            let entries: Vec<(String, Value<'v>)> = map
                .into_iter()
                .map(|(k, v)| (k, json_to_starlark(heap, v)))
                .collect();
            heap.alloc(AllocDict(entries))
        }
    }
}
