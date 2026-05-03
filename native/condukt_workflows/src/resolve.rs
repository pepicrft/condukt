use rustler::Term;

use crate::errors::{WorkflowsError, WorkflowsResult};

pub(crate) fn resolve(
    _root: String,
    _requirements: Term<'_>,
    _index: Term<'_>,
) -> WorkflowsResult<Vec<(String, String)>> {
    Err(WorkflowsError::NotImplemented)
}
