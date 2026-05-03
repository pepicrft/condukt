//! Rustler NIF for Condukt workflows.
//!
//! The crate owns four dirty-scheduler entry points:
//!
//! * Starlark evaluation.
//! * Starlark parse-only validation.
//! * PubGrub dependency resolution.
//! * Deterministic content-addressed tree hashing.

use rustler::{Env, NifResult, Term};

use crate::errors::EncodeResult;

mod errors;
mod eval;
mod hash;
mod resolve;

pub(crate) mod atoms {
    rustler::atoms! {
        ok,
        error,
        parse_error,
        eval_error,
        no_solution,
        missing_load,
        invalid_url,
        invalid_version,
        io_error,
        not_found,
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn eval<'a>(
    env: Env<'a>,
    source: String,
    filename: String,
    globals: Term<'a>,
) -> NifResult<Term<'a>> {
    Ok(eval::eval(source, filename, globals).encode(env))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn parse_only<'a>(env: Env<'a>, source: String, filename: String) -> NifResult<Term<'a>> {
    Ok(eval::parse_only(source, filename).encode(env))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn resolve<'a>(
    env: Env<'a>,
    root: String,
    requirements: Term<'a>,
    index: Term<'a>,
) -> NifResult<Term<'a>> {
    Ok(resolve::resolve(root, requirements, index).encode(env))
}

#[rustler::nif(schedule = "DirtyIo")]
fn sha256_tree<'a>(env: Env<'a>, root_dir: String) -> NifResult<Term<'a>> {
    Ok(hash::sha256_tree(root_dir).encode(env))
}

rustler::init!("Elixir.Condukt.Workflows.NIF");
