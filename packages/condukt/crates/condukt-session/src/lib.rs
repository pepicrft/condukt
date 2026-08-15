use std::sync::Arc;

use condukt_inference::{InferenceError, InferenceProvider, ToolDefinition};
pub use condukt_protocol::Message;

mod host;

pub use host::{CompletionRequest, HostSession, HostSessionError, HostTurn, ToolOutput};

/// What the agent did on the way to its final answer. The host uses
/// these events to render tool calls and results next to the model's
/// text in the document.
#[derive(Clone, Debug)]
pub enum AgentEvent {
    /// The model emitted text. It may be interleaved with tool calls.
    Text(String),
    /// The model asked the host to run a tool.
    ToolCall { name: String, arguments: String },
    /// The host ran a tool and is feeding the result back to the model.
    ToolResult {
        name: String,
        output: String,
        error: Option<String>,
    },
}

pub struct Session<P> {
    provider: P,
    history: Vec<Message>,
}

const MAX_AGENT_ITERATIONS: usize = 16;

impl<P: InferenceProvider> Session<P> {
    pub fn new(provider: P) -> Self {
        Self {
            provider,
            history: Vec::new(),
        }
    }

    /// Start a conversation with host-provided operating instructions.
    pub fn with_system_prompt(provider: P, prompt: impl Into<String>) -> Self {
        Self {
            provider,
            history: vec![Message::system(prompt)],
        }
    }
    pub fn history(&self) -> &[Message] {
        &self.history
    }
    pub fn provider_name(&self) -> &str {
        self.provider.name()
    }

    pub fn submit(&mut self, prompt: impl Into<String>) -> Result<Message, InferenceError> {
        self.history.push(Message::user(prompt));
        let response = self.provider.complete(&self.history, &[])?;
        self.history.push(response.clone());
        Ok(response)
    }

    /// Run the agent loop: the model is asked to respond, tool calls
    /// are executed through the provided closure, and the loop continues
    /// until the model produces a final text answer. `on_event` is
    /// invoked for every text chunk, tool call, and tool result so the
    /// host can stream them into the document.
    pub fn submit_with_tools<F>(
        &mut self,
        prompt: impl Into<String>,
        tool_definitions: Arc<Vec<ToolDefinition>>,
        tools: &dyn ToolDispatcher,
        on_event: &mut F,
    ) -> Result<Message, InferenceError>
    where
        F: FnMut(AgentEvent),
    {
        self.history.push(Message::user(prompt));
        for _ in 0..MAX_AGENT_ITERATIONS {
            let response = self
                .provider
                .complete(&self.history, tool_definitions.as_ref())?;
            // Emit any text the model produced alongside tool calls.
            if !response.content.is_empty() {
                on_event(AgentEvent::Text(response.content.clone()));
            }
            // Store the assistant turn so the next call has the full
            // transcript including tool_call ids.
            self.history.push(response.clone());
            let Some(calls) = response.tool_calls.clone() else {
                return Ok(response);
            };
            for call in calls {
                on_event(AgentEvent::ToolCall {
                    name: call.name.clone(),
                    arguments: call.arguments.clone(),
                });
                let result = tools.dispatch(&call.name, &call.arguments);
                match &result {
                    Ok(output) => on_event(AgentEvent::ToolResult {
                        name: call.name.clone(),
                        output: output.clone(),
                        error: None,
                    }),
                    Err(error) => on_event(AgentEvent::ToolResult {
                        name: call.name.clone(),
                        output: String::new(),
                        error: Some(error.clone()),
                    }),
                }
                let result_content = match result {
                    Ok(output) => output,
                    Err(error) => error,
                };
                self.history
                    .push(Message::tool_result(&call.id, result_content));
            }
        }
        Err(InferenceError::Request(
            "agent loop exceeded maximum iterations without producing a final answer".into(),
        ))
    }
}

/// Bridge from a `ToolCall` (name + JSON arguments) to a textual result.
/// The session does not know about specific tool implementations, so the
/// host provides a dispatcher that resolves the call to a string.
pub trait ToolDispatcher {
    fn dispatch(&self, name: &str, arguments_json: &str) -> Result<String, String>;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn system_prompt_is_the_first_history_message() {
        struct Provider;
        impl InferenceProvider for Provider {
            fn name(&self) -> &str {
                "test"
            }

            fn complete(
                &mut self,
                _history: &[Message],
                _tools: &[ToolDefinition],
            ) -> Result<Message, InferenceError> {
                Ok(Message::assistant("done"))
            }
        }

        let session = Session::with_system_prompt(Provider, "be useful");
        assert_eq!(session.history()[0], Message::system("be useful"));
    }
}
