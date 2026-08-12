//! Headless Agent Client Protocol server.
//!
//! The Agent Client Protocol uses JSON-RPC over standard input and output for
//! local agents. Keep this module free of terminal UI concerns: an editor owns
//! the user interface while Condukt owns the inference session and tools.

use std::{
    collections::HashMap,
    path::PathBuf,
    sync::{Arc, Mutex},
};

use crate::agent_prompt::CODING_AGENT_PROMPT;
use crate::local_tools::LocalToolSet;

use agent_client_protocol::schema::v1::{
    AgentCapabilities, ContentBlock, ContentChunk, Implementation, InitializeRequest,
    InitializeResponse, NewSessionRequest, NewSessionResponse, PromptRequest, PromptResponse,
    SessionId, SessionNotification, SessionUpdate, StopReason,
};
use agent_client_protocol::{Agent, Client, ConnectionTo, Result as AcpResult, Stdio};
use condukt_inference::ToolDefinition;
use condukt_openrouter::OpenRouterInferenceProvider;
use condukt_session::{AgentEvent, Session};

const AGENT_NAME: &str = "condukt";

type Sessions = Arc<Mutex<HashMap<SessionId, Arc<Mutex<HeadlessSession>>>>>;

/// Run Condukt as a local [Agent Client Protocol](https://agentclientprotocol.com/)
/// agent. The protocol transport is exclusively standard input and output.
pub async fn run() -> AcpResult<()> {
    let sessions: Sessions = Arc::new(Mutex::new(HashMap::new()));
    let next_session = Arc::new(Mutex::new(0_u64));
    let new_session_store = Arc::clone(&sessions);

    Agent
        .builder()
        .name(AGENT_NAME)
        .on_receive_request(
            async move |initialize: InitializeRequest, responder, _connection| {
                responder.respond(
                    InitializeResponse::new(initialize.protocol_version)
                        .agent_capabilities(AgentCapabilities::new())
                        .agent_info(
                            Implementation::new(AGENT_NAME, env!("CARGO_PKG_VERSION"))
                                .title("Condukt"),
                        ),
                )
            },
            agent_client_protocol::on_receive_request!(),
        )
        .on_receive_request(
            async move |request: NewSessionRequest, responder, _connection| {
                let session_id = {
                    let mut next = next_session.lock().expect("session counter mutex poisoned");
                    *next += 1;
                    SessionId::new(format!("condukt-{}", *next))
                };
                let session = HeadlessSession::new(request.cwd);
                new_session_store
                    .lock()
                    .expect("session store mutex poisoned")
                    .insert(session_id.clone(), Arc::new(Mutex::new(session)));
                responder.respond(NewSessionResponse::new(session_id))
            },
            agent_client_protocol::on_receive_request!(),
        )
        .on_receive_request(
            async move |request: PromptRequest, responder, connection| {
                let prompt = prompt_text(&request.prompt);
                let session_id = request.session_id.clone();
                let result =
                    submit_prompt(&sessions, prompt, session_id.clone(), connection.clone()).await;

                match result {
                    Some(Ok(())) => responder.respond(PromptResponse::new(StopReason::EndTurn)),
                    Some(Err(error)) => {
                        connection.send_notification(SessionNotification::new(
                            session_id,
                            SessionUpdate::AgentMessageChunk(ContentChunk::new(error.into())),
                        ))?;
                        responder.respond(PromptResponse::new(StopReason::EndTurn))
                    }
                    None => responder.respond(PromptResponse::new(StopReason::Refusal)),
                }
            },
            agent_client_protocol::on_receive_request!(),
        )
        .connect_to(Stdio::new())
        .await
}

async fn submit_prompt(
    sessions: &Sessions,
    prompt: String,
    session_id: SessionId,
    connection: ConnectionTo<Client>,
) -> Option<Result<(), String>> {
    // Hold the map lock only long enough to clone this session's handle.
    // Provider calls and local commands can take seconds, so they must not
    // serialize unrelated sessions.
    let session = find_session(sessions, &session_id)?;

    match tokio::task::spawn_blocking(move || {
        session
            .lock()
            .expect("individual session mutex poisoned")
            .submit(prompt, |event| {
                if let AgentEvent::Text(text) = event {
                    let _ = connection.send_notification(SessionNotification::new(
                        session_id.clone(),
                        SessionUpdate::AgentMessageChunk(ContentChunk::new(text.into())),
                    ));
                }
            })
    })
    .await
    {
        Ok(result) => Some(result),
        Err(error) => Some(Err(format!("session worker failed: {error}"))),
    }
}

fn find_session(
    sessions: &Sessions,
    session_id: &SessionId,
) -> Option<Arc<Mutex<HeadlessSession>>> {
    sessions
        .lock()
        .expect("session store mutex poisoned")
        .get(session_id)
        .cloned()
}

/// Per-ACP-session state. The editor supplies the working directory when it
/// creates the session, so local tools are always scoped to that workspace.
struct HeadlessSession {
    session: Result<Session<OpenRouterInferenceProvider>, String>,
    definitions: Arc<Vec<ToolDefinition>>,
    tools: LocalToolSet,
}

impl HeadlessSession {
    fn new(root: PathBuf) -> Self {
        let tools = LocalToolSet::new(root);
        let definitions = tools.definitions();
        let session = OpenRouterInferenceProvider::from_saved_key()
            .map_err(|error| format!("Could not load the OpenRouter connection: {error}"))
            .and_then(|provider| {
                provider
                    .map(|provider| Session::with_system_prompt(provider, CODING_AGENT_PROMPT))
                    .ok_or_else(|| "Condukt is not connected. Run `condukt connect openrouter --api-key <key>` first.".to_string())
            });
        Self {
            session,
            definitions,
            tools,
        }
    }

    fn submit<F>(&mut self, prompt: String, mut on_event: F) -> Result<(), String>
    where
        F: FnMut(AgentEvent),
    {
        let session = self.session.as_mut().map_err(|error| error.clone())?;
        session
            .submit_with_tools(
                prompt,
                Arc::clone(&self.definitions),
                &self.tools,
                &mut |event| on_event(event),
            )
            .map(|_| ())
            .map_err(|error| error.to_string())
    }
}

fn prompt_text(blocks: &[ContentBlock]) -> String {
    blocks
        .iter()
        .map(|block| match block {
            ContentBlock::Text(text) => text.text.clone(),
            ContentBlock::ResourceLink(link) => format!("[{}]({})", link.name, link.uri),
            _ => "[Unsupported prompt content omitted]".to_string(),
        })
        .collect::<Vec<_>>()
        .join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;
    use agent_client_protocol::schema::v1::{ResourceLink, TextContent};

    #[test]
    fn prompt_text_preserves_text_and_resource_links() {
        let prompt = prompt_text(&[
            ContentBlock::Text(TextContent::new("Inspect this:")),
            ContentBlock::ResourceLink(ResourceLink::new("readme", "file:///workspace/README.md")),
        ]);
        assert_eq!(
            prompt,
            "Inspect this:\n[readme](file:///workspace/README.md)"
        );
    }

    #[test]
    fn finding_a_session_releases_the_shared_map_lock() {
        let session_id = SessionId::new("test-session");
        let tools = LocalToolSet::new(std::env::temp_dir());
        let session = HeadlessSession {
            session: Err("not connected".to_string()),
            definitions: tools.definitions(),
            tools,
        };
        let sessions: Sessions = Arc::new(Mutex::new(HashMap::from([(
            session_id.clone(),
            Arc::new(Mutex::new(session)),
        )])));

        let session = find_session(&sessions, &session_id).expect("session exists");
        let _session_guard = session.lock().expect("individual session lock");
        assert!(
            sessions.try_lock().is_ok(),
            "locking one session must not retain the shared map lock"
        );
    }
}
