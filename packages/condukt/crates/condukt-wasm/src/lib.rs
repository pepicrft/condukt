use condukt_inference::ToolDefinition;
use condukt_protocol::Message;
use condukt_session::{HostSession, ToolOutput};
use serde::Deserialize;
use wasm_bindgen::prelude::*;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct SessionOptions {
    #[serde(default)]
    system_prompt: Option<String>,
    #[serde(default)]
    tools: Vec<ToolDefinition>,
}

/// WebAssembly boundary for Condukt's provider-neutral agent state machine.
///
/// Inference, authentication, and tools stay in the JavaScript host. This type
/// only owns the transcript and validates the order of model and tool steps.
#[wasm_bindgen]
pub struct AgentSession {
    inner: HostSession,
}

#[wasm_bindgen]
impl AgentSession {
    #[wasm_bindgen(constructor)]
    pub fn new(options: JsValue) -> Result<AgentSession, JsValue> {
        let options: SessionOptions =
            serde_wasm_bindgen::from_value(options).map_err(|error| js_error(error.to_string()))?;
        Ok(Self {
            inner: HostSession::new(options.system_prompt, options.tools),
        })
    }

    /// Add a user message and return the next provider-neutral request.
    pub fn submit(&mut self, prompt: String) -> Result<JsValue, JsValue> {
        let request = self.inner.submit(prompt).map_err(session_error)?;
        serde_wasm_bindgen::to_value(&request).map_err(|error| js_error(error.to_string()))
    }

    /// Accept the assistant message returned by the host's inference service.
    pub fn receive_completion(&mut self, response: JsValue) -> Result<JsValue, JsValue> {
        let response: Message = serde_wasm_bindgen::from_value(response)
            .map_err(|error| js_error(error.to_string()))?;
        let turn = self
            .inner
            .receive_completion(response)
            .map_err(session_error)?;
        serde_wasm_bindgen::to_value(&turn).map_err(|error| js_error(error.to_string()))
    }

    /// Accept the browser host's tool results and return the next request.
    pub fn receive_tool_outputs(&mut self, outputs: JsValue) -> Result<JsValue, JsValue> {
        let outputs: Vec<ToolOutput> =
            serde_wasm_bindgen::from_value(outputs).map_err(|error| js_error(error.to_string()))?;
        let request = self
            .inner
            .receive_tool_outputs(outputs)
            .map_err(session_error)?;
        serde_wasm_bindgen::to_value(&request).map_err(|error| js_error(error.to_string()))
    }

    pub fn history(&self) -> Result<JsValue, JsValue> {
        serde_wasm_bindgen::to_value(self.inner.history())
            .map_err(|error| js_error(error.to_string()))
    }
}

fn session_error(error: impl std::fmt::Display) -> JsValue {
    js_error(error.to_string())
}

fn js_error(message: String) -> JsValue {
    js_sys::Error::new(&message).into()
}
