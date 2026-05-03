use rustler::Term;

use crate::errors::{WorkflowsError, WorkflowsResult};

pub(crate) fn eval(
    _source: String,
    _filename: String,
    _globals: Term<'_>,
) -> WorkflowsResult<String> {
    Err(WorkflowsError::NotImplemented)
}

pub(crate) fn parse_only(_source: String, _filename: String) -> WorkflowsResult<String> {
    Err(WorkflowsError::NotImplemented)
}
