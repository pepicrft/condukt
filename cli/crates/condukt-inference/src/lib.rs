use condukt_protocol::Message;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum InferenceError {
    #[error("the provider is not connected")]
    NotConnected,
    #[error("provider request failed: {0}")]
    Request(String),
}

/// OpenAI-compatible tool definition sent to the provider. Each entry is
/// passed through to the `tools` array of the chat completion request.
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ToolDefinition {
    pub name: String,
    pub description: String,
    /// JSON Schema for the function arguments.
    pub parameters: Value,
}

pub trait InferenceProvider {
    fn name(&self) -> &str;
    fn complete(
        &mut self,
        history: &[Message],
        tools: &[ToolDefinition],
    ) -> Result<Message, InferenceError>;
}
