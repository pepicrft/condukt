use std::collections::BTreeMap;

use rustler::{Encoder, Env, Term};
use serde_json::Value as JsonValue;

#[derive(Clone, Debug, PartialEq)]
pub(crate) enum NifValue {
    Null,
    Bool(bool),
    Integer(i64),
    Float(f64),
    String(String),
    List(Vec<NifValue>),
    Map(BTreeMap<String, NifValue>),
}

impl Encoder for NifValue {
    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        match self {
            NifValue::Null => Option::<String>::None.encode(env),
            NifValue::Bool(value) => value.encode(env),
            NifValue::Integer(value) => value.encode(env),
            NifValue::Float(value) => value.encode(env),
            NifValue::String(value) => value.encode(env),
            NifValue::List(values) => values.encode(env),
            NifValue::Map(values) => {
                let mut map = Term::map_new(env);

                for (key, value) in values {
                    map = map
                        .map_put(key, value)
                        .expect("failed to encode workflow map value");
                }

                map
            }
        }
    }
}

impl From<JsonValue> for NifValue {
    fn from(value: JsonValue) -> Self {
        match value {
            JsonValue::Null => NifValue::Null,
            JsonValue::Bool(value) => NifValue::Bool(value),
            JsonValue::Number(value) => {
                if let Some(value) = value.as_i64() {
                    NifValue::Integer(value)
                } else {
                    NifValue::Float(value.as_f64().unwrap_or_default())
                }
            }
            JsonValue::String(value) => NifValue::String(value),
            JsonValue::Array(values) => {
                NifValue::List(values.into_iter().map(NifValue::from).collect())
            }
            JsonValue::Object(values) => NifValue::Map(
                values
                    .into_iter()
                    .map(|(key, value)| (key, NifValue::from(value)))
                    .collect(),
            ),
        }
    }
}
