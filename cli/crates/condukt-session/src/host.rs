use condukt_inference::ToolDefinition;
use condukt_protocol::{Message, Role, ToolCall};
use serde::{Deserialize, Serialize};
use thiserror::Error;

const MAX_HOST_ITERATIONS: usize = 16;

/// Provider-neutral request produced by the agent state machine.
///
/// A host translates this request to its inference service. The host owns the
/// credential, network transport, model choice, and retry policy.
#[derive(Clone, Debug, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct CompletionRequest {
    pub messages: Vec<Message>,
    pub tools: Vec<ToolDefinition>,
}

/// Result of accepting a model response.
#[derive(Clone, Debug, Serialize, PartialEq)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum HostTurn {
    Complete {
        message: Message,
    },
    RunTools {
        message: Message,
        calls: Vec<ToolCall>,
    },
}

/// A browser or application host's result for one requested tool call.
#[derive(Clone, Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ToolOutput {
    pub tool_call_id: String,
    pub content: String,
    #[serde(default)]
    pub is_error: bool,
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum HostSessionError {
    #[error("the session is already processing a turn")]
    TurnInProgress,
    #[error("the session is not waiting for a model response")]
    NotWaitingForCompletion,
    #[error("the session is not waiting for tool results")]
    NotWaitingForTools,
    #[error("the model response must have the assistant role")]
    InvalidResponseRole,
    #[error("tool results did not match the requested tool calls")]
    InvalidToolResults,
    #[error("agent loop exceeded the maximum number of model requests")]
    IterationLimit,
}

/// Host-driven agent state for environments where inference and tools are
/// asynchronous capabilities supplied outside Rust, such as a web browser.
pub struct HostSession {
    history: Vec<Message>,
    tools: Vec<ToolDefinition>,
    awaiting_completion: bool,
    awaiting_tools: Option<Vec<ToolCall>>,
    iterations: usize,
}

impl HostSession {
    pub fn new(system_prompt: Option<String>, tools: Vec<ToolDefinition>) -> Self {
        let history = system_prompt
            .filter(|prompt| !prompt.trim().is_empty())
            .map(Message::system)
            .into_iter()
            .collect();

        Self {
            history,
            tools,
            awaiting_completion: false,
            awaiting_tools: None,
            iterations: 0,
        }
    }

    pub fn history(&self) -> &[Message] {
        &self.history
    }

    /// Begin one user turn and return the request the host should complete.
    pub fn submit(
        &mut self,
        prompt: impl Into<String>,
    ) -> Result<CompletionRequest, HostSessionError> {
        if self.awaiting_completion || self.awaiting_tools.is_some() {
            return Err(HostSessionError::TurnInProgress);
        }
        self.iterations = 0;
        self.history.push(Message::user(prompt));
        self.next_completion_request()
    }

    /// Accept an assistant message from the host's inference service.
    pub fn receive_completion(&mut self, response: Message) -> Result<HostTurn, HostSessionError> {
        if !self.awaiting_completion {
            return Err(HostSessionError::NotWaitingForCompletion);
        }
        if response.role != Role::Assistant {
            return Err(HostSessionError::InvalidResponseRole);
        }

        self.awaiting_completion = false;
        self.history.push(response.clone());
        let calls = response.tool_calls.clone().unwrap_or_default();
        if calls.is_empty() {
            return Ok(HostTurn::Complete { message: response });
        }

        self.awaiting_tools = Some(calls.clone());
        Ok(HostTurn::RunTools {
            message: response,
            calls,
        })
    }

    /// Accept one result per requested tool call and continue the agent loop.
    pub fn receive_tool_outputs(
        &mut self,
        outputs: Vec<ToolOutput>,
    ) -> Result<CompletionRequest, HostSessionError> {
        let calls = self
            .awaiting_tools
            .take()
            .ok_or(HostSessionError::NotWaitingForTools)?;

        let results_match = calls.len() == outputs.len()
            && calls.iter().zip(&outputs).all(|(call, output)| {
                call.id == output.tool_call_id
                    && outputs
                        .iter()
                        .filter(|candidate| candidate.tool_call_id == output.tool_call_id)
                        .count()
                        == 1
            });
        if !results_match {
            self.awaiting_tools = Some(calls);
            return Err(HostSessionError::InvalidToolResults);
        }

        for output in outputs {
            let content = if output.is_error {
                format!("Tool error: {}", output.content)
            } else {
                output.content
            };
            self.history
                .push(Message::tool_result(output.tool_call_id, content));
        }

        self.next_completion_request()
    }

    fn next_completion_request(&mut self) -> Result<CompletionRequest, HostSessionError> {
        if self.iterations >= MAX_HOST_ITERATIONS {
            return Err(HostSessionError::IterationLimit);
        }
        self.iterations += 1;
        self.awaiting_completion = true;
        Ok(CompletionRequest {
            messages: self.history.clone(),
            tools: self.tools.clone(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use condukt_protocol::ToolCall;
    use serde_json::json;

    fn tool() -> ToolDefinition {
        ToolDefinition {
            name: "read_page".into(),
            description: "Read the current page".into(),
            parameters: json!({"type": "object", "properties": {}}),
        }
    }

    #[test]
    fn host_drives_completion_and_tool_steps() {
        let mut session = HostSession::new(Some("Be useful".into()), vec![tool()]);
        let request = session.submit("What is here?").unwrap();
        assert_eq!(request.messages.len(), 2);
        assert_eq!(request.tools, vec![tool()]);

        let call = ToolCall {
            id: "call-1".into(),
            name: "read_page".into(),
            arguments: "{}".into(),
        };
        let turn = session
            .receive_completion(Message::assistant_with_tool_calls("", vec![call.clone()]))
            .unwrap();
        assert_eq!(
            turn,
            HostTurn::RunTools {
                message: Message::assistant_with_tool_calls("", vec![call]),
                calls: vec![ToolCall {
                    id: "call-1".into(),
                    name: "read_page".into(),
                    arguments: "{}".into(),
                }],
            }
        );

        let request = session
            .receive_tool_outputs(vec![ToolOutput {
                tool_call_id: "call-1".into(),
                content: "Condukt is portable".into(),
                is_error: false,
            }])
            .unwrap();
        assert_eq!(request.messages.last().unwrap().role, Role::Tool);

        let done = session
            .receive_completion(Message::assistant("Condukt runs in your browser."))
            .unwrap();
        assert!(matches!(done, HostTurn::Complete { .. }));
    }

    #[test]
    fn mismatched_tool_results_leave_the_session_recoverable() {
        let mut session = HostSession::new(None, vec![tool()]);
        session.submit("hello").unwrap();
        session
            .receive_completion(Message::assistant_with_tool_calls(
                "",
                vec![ToolCall {
                    id: "expected".into(),
                    name: "read_page".into(),
                    arguments: "{}".into(),
                }],
            ))
            .unwrap();

        let error = session
            .receive_tool_outputs(vec![ToolOutput {
                tool_call_id: "other".into(),
                content: "nope".into(),
                is_error: false,
            }])
            .unwrap_err();
        assert_eq!(error, HostSessionError::InvalidToolResults);

        session
            .receive_tool_outputs(vec![ToolOutput {
                tool_call_id: "expected".into(),
                content: "recovered".into(),
                is_error: false,
            }])
            .unwrap();
    }

    #[test]
    fn invalid_response_role_leaves_the_session_recoverable() {
        let mut session = HostSession::new(None, vec![]);
        session.submit("hello").unwrap();

        let error = session
            .receive_completion(Message::user("not valid"))
            .unwrap_err();
        assert_eq!(error, HostSessionError::InvalidResponseRole);

        assert!(matches!(
            session
                .receive_completion(Message::assistant("recovered"))
                .unwrap(),
            HostTurn::Complete { .. }
        ));
    }

    #[test]
    fn repeated_tool_calls_stop_at_the_iteration_limit() {
        let mut session = HostSession::new(None, vec![tool()]);
        session.submit("loop").unwrap();

        for iteration in 0..MAX_HOST_ITERATIONS {
            let call_id = format!("call-{iteration}");
            session
                .receive_completion(Message::assistant_with_tool_calls(
                    "",
                    vec![ToolCall {
                        id: call_id.clone(),
                        name: "read_page".into(),
                        arguments: "{}".into(),
                    }],
                ))
                .unwrap();

            let result = session.receive_tool_outputs(vec![ToolOutput {
                tool_call_id: call_id,
                content: "again".into(),
                is_error: false,
            }]);

            if iteration + 1 == MAX_HOST_ITERATIONS {
                assert_eq!(result.unwrap_err(), HostSessionError::IterationLimit);
            } else {
                result.unwrap();
            }
        }
    }
}
