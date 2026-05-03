use rustler::{Encoder, Env, Term};
use thiserror::Error;

use crate::atoms;

#[derive(Debug, Error)]
pub(crate) enum WorkflowsError {
    #[error("not implemented")]
    NotImplemented,
    #[error("parse error: {0}")]
    Parse(String),
    #[error("eval error: {0}")]
    Eval(String),
    #[error("missing load: {0}")]
    MissingLoad(String),
    #[error("not found: {0}")]
    NotFound(String),
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
    #[error("I/O error: {0}")]
    WalkDir(#[from] walkdir::Error),
}

pub(crate) type WorkflowsResult<T> = Result<T, WorkflowsError>;

impl WorkflowsError {
    fn kind(&self) -> rustler::Atom {
        match self {
            WorkflowsError::NotImplemented => atoms::error(),
            WorkflowsError::Parse(_) => atoms::parse_error(),
            WorkflowsError::Eval(_) => atoms::eval_error(),
            WorkflowsError::MissingLoad(_) => atoms::missing_load(),
            WorkflowsError::NotFound(_) => atoms::not_found(),
            WorkflowsError::Io(_) | WorkflowsError::WalkDir(_) => atoms::io_error(),
        }
    }
}

impl<T> EncodeResult for WorkflowsResult<T>
where
    T: Encoder,
{
    fn encode<'a>(self, env: Env<'a>) -> Term<'a> {
        match self {
            Ok(value) => (atoms::ok(), value).encode(env),
            Err(error) => (atoms::error(), (error.kind(), error.to_string())).encode(env),
        }
    }
}

pub(crate) trait EncodeResult {
    fn encode<'a>(self, env: Env<'a>) -> Term<'a>;
}
