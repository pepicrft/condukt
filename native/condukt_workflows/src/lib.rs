//! Rustler NIF for Condukt workflows.
//!
//! Workflows are Starlark files that declare a `run(inputs)` function. The
//! Rust runtime evaluates them on a dedicated OS thread and suspends the
//! Starlark VM whenever a builtin like `run_cmd(...)` is called: the request
//! is forwarded to the BEAM, the host performs the side effect, and the
//! response is fed back to Starlark which resumes execution with the value.

use rustler::{Encoder, Env, NifResult, ResourceArc, Term};
use serde_json::Value as JsonValue;

use crate::error::{EncodeResult, WorkflowsError, WorkflowsResult};
use crate::runtime::{Event, RunHandle};

mod error;
mod parse;
mod runtime;
mod terms;
mod value;

pub(crate) mod atoms {
    rustler::atoms! {
        ok,
        error,
        suspended,
        done,
        parse_error,
        eval_error,
        invalid_arguments,
        invalid_response,
        runtime_error,
        cancelled,
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn start_run<'a>(
    env: Env<'a>,
    source: String,
    filename: String,
    inputs_json: String,
) -> NifResult<Term<'a>> {
    let result = (|| {
        let inputs = parse_json(&inputs_json, "inputs")?;
        runtime::start_run(source, filename, inputs)
    })();

    match result {
        Ok((handle, event)) => Ok(start_run_ok(env, handle, event)),
        Err(error) => Ok(WorkflowsResult::<()>::Err(error).encode(env)),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn resume_run<'a>(
    env: Env<'a>,
    handle: ResourceArc<RunHandle>,
    response_json: String,
) -> NifResult<Term<'a>> {
    let result = (|| {
        let response = parse_json(&response_json, "response")?;
        runtime::resume_run(&handle, response)
    })();

    match result {
        Ok(event) => Ok(encode_event(env, event)),
        Err(error) => Ok(WorkflowsResult::<()>::Err(error).encode(env)),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn cancel_run<'a>(env: Env<'a>, handle: ResourceArc<RunHandle>) -> NifResult<Term<'a>> {
    runtime::cancel_run(&handle);
    Ok(atoms::ok().encode(env))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn parse_only<'a>(env: Env<'a>, source: String, filename: String) -> NifResult<Term<'a>> {
    Ok(parse::parse_only(source, filename).encode(env))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn check<'a>(env: Env<'a>, source: String, filename: String) -> NifResult<Term<'a>> {
    Ok(parse::check(source, filename).encode(env))
}

fn parse_json(input: &str, label: &str) -> WorkflowsResult<JsonValue> {
    serde_json::from_str(input)
        .map_err(|error| WorkflowsError::InvalidArguments(format!("{label}: {error}")))
}

fn start_run_ok<'a>(env: Env<'a>, handle: ResourceArc<RunHandle>, event: Event) -> Term<'a> {
    let event_term = encode_event_payload(env, event);
    (atoms::ok(), (handle, event_term)).encode(env)
}

fn encode_event<'a>(env: Env<'a>, event: Event) -> Term<'a> {
    (atoms::ok(), encode_event_payload(env, event)).encode(env)
}

fn encode_event_payload<'a>(env: Env<'a>, event: Event) -> Term<'a> {
    match event {
        Event::Suspend(value) => (atoms::suspended(), serialize_json(value)).encode(env),
        Event::Done(value) => (atoms::done(), serialize_json(value)).encode(env),
        Event::Error(message) => (atoms::error(), message).encode(env),
    }
}

fn serialize_json(value: JsonValue) -> String {
    serde_json::to_string(&value).unwrap_or_else(|_| "null".to_owned())
}

fn on_load(env: Env, _: Term) -> bool {
    let _ = rustler::resource!(RunHandle, env);
    true
}

rustler::init!("Elixir.Condukt.Workflows.NIF", load = on_load);
