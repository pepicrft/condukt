use std::{io, sync::OnceLock, time::Duration};

use condukt_inference::{InferenceError, InferenceProvider, ToolDefinition};
use condukt_protocol::{Message, Role, ToolCall};
use serde_json::{Value, json};

const DEFAULT_MODEL: &str = "minimax/minimax-m3";
/// End-to-end timeout for every OpenRouter HTTP call. The chat endpoint
/// usually returns in a couple of seconds; 30s is generous but still
/// bounded so a hung connection can't freeze the agent forever.
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);
/// Endpoint used to confirm a saved key is still accepted. A 200 here
/// means the key authenticates; a 401 means the user has to reconnect.
const AUTH_KEY_URL: &str = "https://openrouter.ai/api/v1/auth/key";

mod credentials;

pub use credentials::{CredentialStore, FileCredentialStore, import_pi_openrouter_credential};

/// Shared ureq agent so the connection pool and timeouts are configured
/// in one place. The agent is created on first use and reused for the
/// lifetime of the process. Exposed so the OAuth flow can reuse the
/// same timeout configuration.
pub fn shared_agent() -> &'static ureq::Agent {
    static AGENT: OnceLock<ureq::Agent> = OnceLock::new();
    AGENT.get_or_init(|| {
        let config = ureq::Agent::config_builder()
            .timeout_global(Some(REQUEST_TIMEOUT))
            .build();
        ureq::Agent::new_with_config(config)
    })
}

pub struct OpenRouterInferenceProvider {
    api_key: String,
    model: String,
}

impl OpenRouterInferenceProvider {
    pub fn new(api_key: impl Into<String>) -> Self {
        Self {
            api_key: api_key.into(),
            model: DEFAULT_MODEL.into(),
        }
    }

    pub fn from_saved_key() -> io::Result<Option<Self>> {
        Self::from_credential_store(&FileCredentialStore::from_environment()?)
    }

    /// Construct a provider from a host-supplied credential store.
    pub fn from_credential_store(store: &dyn CredentialStore) -> io::Result<Option<Self>> {
        store.load().map(|key| key.map(Self::new))
    }

    /// Identifier shown in the conversation transcript for this provider.
    pub fn model_name(&self) -> &str {
        &self.model
    }

    /// Confirm the key authenticates against `/api/v1/auth/key`. Used
    /// right after `save_key` so we don't tell the user the connection
    /// worked when OpenRouter would have rejected every subsequent
    /// request. Returns a human-readable error otherwise.
    pub fn validate(&self) -> Result<(), String> {
        let url = AUTH_KEY_URL_OVERRIDE
            .lock()
            .unwrap()
            .clone()
            .unwrap_or_else(|| AUTH_KEY_URL.to_string());
        let response = shared_agent()
            .get(&url)
            .header("Authorization", &format!("Bearer {}", self.api_key))
            .call();
        match response {
            Ok(mut response) => {
                // Drain the body so the connection can be returned to the
                // pool. We don't need the contents.
                let _ = response.body_mut().read_to_string();
                Ok(())
            }
            Err(ureq::Error::StatusCode(401)) => Err(
                "The saved OpenRouter key is no longer valid. Run /connect to re-authenticate."
                    .to_string(),
            ),
            Err(ureq::Error::StatusCode(status)) => Err(format!(
                "OpenRouter returned HTTP {status} while validating the key."
            )),
            Err(error) => Err(format!(
                "Could not reach OpenRouter to validate the key: {error}"
            )),
        }
    }
}

impl InferenceProvider for OpenRouterInferenceProvider {
    fn name(&self) -> &str {
        "OpenRouter"
    }

    fn complete(
        &mut self,
        history: &[Message],
        tools: &[ToolDefinition],
    ) -> Result<Message, InferenceError> {
        let messages: Vec<Value> = history.iter().map(message_to_openai).collect();
        let tools_payload: Vec<Value> = tools
            .iter()
            .map(|tool| {
                json!({
                    "type": "function",
                    "function": {
                        "name": tool.name,
                        "description": tool.description,
                        "parameters": tool.parameters,
                    }
                })
            })
            .collect();
        let mut body = json!({
            "model": self.model,
            "messages": messages,
            "reasoning": { "effort": "high", "exclude": true },
        });
        if !tools_payload.is_empty() {
            body["tools"] = Value::Array(tools_payload);
        }
        let response = shared_agent()
            .post("https://openrouter.ai/api/v1/chat/completions")
            .header("Authorization", &format!("Bearer {}", self.api_key))
            .header("HTTP-Referer", "https://github.com/tuist/condukt")
            .send_json(body)
            .map_err(map_ureq_error)?;
        let mut response_body = response.into_body();
        let value: Value = serde_json::from_str(
            &response_body
                .read_to_string()
                .map_err(|error| InferenceError::Request(error.to_string()))?,
        )
        .map_err(|error| InferenceError::Request(error.to_string()))?;
        let message_value = &value["choices"][0]["message"];
        if let Some(calls) = message_value.get("tool_calls").and_then(Value::as_array) {
            let tool_calls: Vec<ToolCall> = calls
                .iter()
                .map(parse_tool_call)
                .collect::<Result<_, _>>()?;
            let content = message_value
                .get("content")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string();
            return Ok(Message::assistant_with_tool_calls(content, tool_calls));
        }
        let content = message_value
            .get("content")
            .and_then(Value::as_str)
            .ok_or_else(|| {
                InferenceError::Request("response did not include assistant content".into())
            })?;
        Ok(Message::assistant(content))
    }
}

fn message_to_openai(message: &Message) -> Value {
    let mut object = json!({"role": role_name(&message.role), "content": message.content});
    if let Some(calls) = &message.tool_calls {
        let calls: Vec<Value> = calls
            .iter()
            .map(|call| {
                json!({
                    "id": call.id,
                    "type": "function",
                    "function": {
                        "name": call.name,
                        "arguments": call.arguments,
                    }
                })
            })
            .collect();
        object["tool_calls"] = Value::Array(calls);
    }
    if let Some(id) = &message.tool_call_id {
        object["tool_call_id"] = Value::String(id.clone());
    }
    object
}

fn parse_tool_call(value: &Value) -> Result<ToolCall, InferenceError> {
    let id = value
        .get("id")
        .and_then(Value::as_str)
        .ok_or_else(|| InferenceError::Request("tool call missing id".into()))?
        .to_string();
    let function = value
        .get("function")
        .ok_or_else(|| InferenceError::Request("tool call missing function".into()))?;
    let name = function
        .get("name")
        .and_then(Value::as_str)
        .ok_or_else(|| InferenceError::Request("tool call missing name".into()))?
        .to_string();
    let arguments = function
        .get("arguments")
        .and_then(Value::as_str)
        .unwrap_or("{}")
        .to_string();
    Ok(ToolCall {
        id,
        name,
        arguments,
    })
}

pub fn save_key(api_key: &str) -> io::Result<()> {
    FileCredentialStore::from_environment()?.save(api_key)
}

/// Remove the saved key. Used when validation fails so the next
/// `/connect` starts from a clean slate instead of reusing a key that
/// OpenRouter has already rejected.
pub fn delete_key() -> io::Result<()> {
    FileCredentialStore::from_environment()?.delete()
}

pub fn load_key() -> io::Result<Option<String>> {
    FileCredentialStore::from_environment()?.load()
}

fn role_name(role: &Role) -> &'static str {
    match role {
        Role::System => "system",
        Role::User => "user",
        Role::Assistant => "assistant",
        Role::Tool => "tool",
    }
}

/// Translate a ureq error into something a user can act on. A 401 in
/// particular usually means the saved key was revoked or never worked.
fn map_ureq_error(error: ureq::Error) -> InferenceError {
    match error {
        ureq::Error::StatusCode(401) => InferenceError::Request(
            "OpenRouter rejected the saved key. Run /connect to re-authenticate.".into(),
        ),
        ureq::Error::StatusCode(status) => {
            InferenceError::Request(format!("OpenRouter returned HTTP {status}"))
        }
        ureq::Error::Timeout(_) => InferenceError::Request("OpenRouter request timed out.".into()),
        other => InferenceError::Request(other.to_string()),
    }
}

// Indirection so tests can redirect the auth-key URL to a mock server
// without exposing a public setter. `validate` looks at this first,
// then falls back to the real OpenRouter endpoint.
static AUTH_KEY_URL_OVERRIDE: std::sync::Mutex<Option<String>> = std::sync::Mutex::new(None);

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Read, Write};
    use std::net::TcpListener;
    use std::sync::Arc;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::thread;

    /// Spin up a single-shot HTTP server on localhost that replies with
    /// the given status code and body. Returns the base URL (no path)
    /// the server is listening on, plus a counter of how many requests
    /// it has served so tests can assert how often the agent called.
    fn spawn_mock_server(status: u16, body: &'static str) -> (String, Arc<AtomicUsize>) {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
        let port = listener.local_addr().unwrap().port();
        let counter = Arc::new(AtomicUsize::new(0));
        let counter_clone = Arc::clone(&counter);
        thread::spawn(move || {
            // Serve the first request then exit. `validate` is
            // single-shot so we don't need to handle more.
            if let Ok((mut stream, _)) = listener.accept() {
                counter_clone.fetch_add(1, Ordering::SeqCst);
                let mut buf = [0u8; 1024];
                let _ = stream.read(&mut buf);
                let reason = match status {
                    200 => "OK",
                    401 => "Unauthorized",
                    _ => "Status",
                };
                let response = format!(
                    "HTTP/1.1 {status} {reason}\r\nContent-Type: application/json\r\nContent-Length: {len}\r\nConnection: close\r\n\r\n{body}",
                    len = body.len()
                );
                let _ = stream.write_all(response.as_bytes());
                let _ = stream.flush();
            }
        });
        (format!("http://127.0.0.1:{port}"), counter)
    }

    /// Override the auth-key URL the `validate` function uses for the
    /// duration of the call. The static is restored at the end of the
    /// test so other tests aren't affected.
    fn with_auth_url<F: FnOnce()>(url: &str, body: F) {
        // SAFETY: the tests run in parallel by default, but `validate`
        // is only called from one test at a time because we serialize
        // on the same atomic below. In practice `cargo test` runs tests
        // in parallel within a process; we use a process-global mutex
        // to keep the URL swap race-free.
        use std::sync::Mutex;
        static LOCK: Mutex<()> = Mutex::new(());
        let _guard = LOCK.lock().unwrap();
        let previous = AUTH_KEY_URL_OVERRIDE
            .lock()
            .unwrap()
            .replace(url.to_string());
        body();
        *AUTH_KEY_URL_OVERRIDE.lock().unwrap() = previous;
    }

    #[test]
    fn map_ureq_error_translates_401_to_a_reauth_hint() {
        let error = ureq::Error::StatusCode(401);
        let message = match map_ureq_error(error) {
            InferenceError::Request(message) => message,
            other => panic!("expected Request, got {other:?}"),
        };
        assert!(message.contains("re-authenticate"), "got: {message}");
    }

    #[test]
    fn map_ureq_error_passes_through_other_status_codes() {
        let error = ureq::Error::StatusCode(500);
        let message = match map_ureq_error(error) {
            InferenceError::Request(message) => message,
            other => panic!("expected Request, got {other:?}"),
        };
        assert!(message.contains("500"), "got: {message}");
    }

    #[test]
    fn map_ureq_error_translates_timeout() {
        let error = ureq::Error::Timeout(ureq::Timeout::Global);
        let message = match map_ureq_error(error) {
            InferenceError::Request(message) => message,
            other => panic!("expected Request, got {other:?}"),
        };
        assert!(
            message.to_lowercase().contains("timed out"),
            "got: {message}"
        );
    }

    #[test]
    fn shared_agent_returns_the_same_instance() {
        let first = shared_agent() as *const _;
        let second = shared_agent() as *const _;
        assert_eq!(first, second, "shared_agent must return the same instance");
    }

    #[test]
    fn validate_returns_ok_for_a_2xx_response() {
        let (base, counter) = spawn_mock_server(200, r#"{"data":{"label":"test-key"}}"#);
        with_auth_url(&format!("{base}/api/v1/auth/key"), || {
            let provider = OpenRouterInferenceProvider::new("sk-or-v1-test");
            let result = provider.validate();
            assert!(result.is_ok(), "expected Ok, got {result:?}");
            assert_eq!(counter.load(Ordering::SeqCst), 1, "expected one request");
        });
    }

    #[test]
    fn validate_rejects_401_with_a_reauth_hint() {
        let (base, _counter) =
            spawn_mock_server(401, r#"{"error":{"message":"User not found.","code":401}}"#);
        with_auth_url(&format!("{base}/api/v1/auth/key"), || {
            let provider = OpenRouterInferenceProvider::new("sk-or-v1-stale");
            let message = provider.validate().expect_err("expected 401 error");
            assert!(
                message.to_lowercase().contains("re-authenticate"),
                "got: {message}"
            );
        });
    }

    #[test]
    fn validate_surfaces_other_status_codes() {
        let (base, _counter) = spawn_mock_server(500, r#"{"error":"oops"}"#);
        with_auth_url(&format!("{base}/api/v1/auth/key"), || {
            let provider = OpenRouterInferenceProvider::new("sk-or-v1-test");
            let message = provider.validate().expect_err("expected 500 error");
            assert!(message.contains("500"), "got: {message}");
        });
    }
}

// Indirection so tests can redirect the auth-key URL to a mock server
// without exposing a public setter. `validate` looks at this first,
// then falls back to the real OpenRouter endpoint.
