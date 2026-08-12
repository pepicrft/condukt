use std::path::PathBuf;
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, Ordering},
    mpsc,
};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use crate::agent_prompt::CODING_AGENT_PROMPT;
use crate::browser::{BrowserOpener, SystemBrowser};
use crate::commands::{SlashCommandKind, help_text, parse_slash_command};
use crate::connection;
use crate::footer::Footer;
use crate::local_tools::LocalToolSet;
use crate::openrouter_oauth as oauth_flow;
use crate::rich_text::RichText;
use crate::theme::THEME;
use condukt_inference::InferenceError;
use condukt_openrouter::OpenRouterInferenceProvider;
use condukt_session::{AgentEvent, Message, Session};
use condukt_tools::workspace_files;
use ratatui::{
    style::{Modifier, Style},
    text::{Line, Span},
};

/// One row in a multi-step selection menu (the connect flow).
#[derive(Clone, Copy)]
pub struct MenuOption {
    pub value: &'static str,
    pub description: &'static str,
}

pub const CONNECT_METHODS: &[MenuOption] = &[
    MenuOption {
        value: "account",
        description: "Sign in with an account",
    },
    MenuOption {
        value: "api-key",
        description: "Sign in with an API key",
    },
];

pub const PROVIDERS: &[MenuOption] = &[MenuOption {
    value: "openrouter",
    description: "OpenRouter",
}];

/// The state machine the TUI walks through.
#[derive(Clone)]
pub enum AppMode {
    Normal,
    /// Choosing how to connect: account vs API key.
    AwaitingConnectMethod {
        selected: usize,
    },
    /// Choosing which provider to connect.
    AwaitingProvider {
        selected: usize,
    },
    /// Awaiting the user to type the API key. `opened_browser` records
    /// whether the host browser was opened for this attempt.
    AwaitingApiKey {
        provider: String,
        opened_browser: bool,
    },
    /// A connection is being validated on a worker thread.
    Connecting,
}

pub struct App {
    /// Active session, shared with the agent worker thread. Wrapped in
    /// `Arc<Mutex<>>` so the worker can borrow it for the duration of
    /// a request without blocking the TUI.
    pub session: Option<Arc<Mutex<Session<OpenRouterInferenceProvider>>>>,
    pub input: String,
    pub document: Vec<Line<'static>>,
    pub mode: AppMode,
    pub show_commands: bool,
    /// Highlighted index inside the filtered slash-command list. Only
    /// meaningful while `show_commands` is true.
    pub slash_selected: Option<usize>,
    pub should_exit: bool,
    /// True while an agent request is in flight. Used to ignore
    /// additional Enter presses and to dim the prompt.
    pub pending: bool,
    pub footer: Footer,
    browser: Box<dyn BrowserOpener>,
    /// Shared tool definitions and dispatch used by every host mode.
    tools: Arc<LocalToolSet>,
    /// Receiver for events from the agent worker thread. `None` when
    /// no request is in flight.
    event_rx: Option<mpsc::Receiver<AgentMessage>>,
    connection_rx: Option<mpsc::Receiver<ConnectionResult>>,
    connection_cancelled: Option<Arc<AtomicBool>>,
    connection_worker: Option<JoinHandle<()>>,
    /// Start time for the prompt-border progress animation.
    pending_started_at: Option<Instant>,
    user_name: String,
    model_name: String,
    /// Number of rows the transcript is offset from its newest entry.
    /// Zero follows new output at the bottom.
    document_scroll_from_bottom: u16,
}

impl App {
    /// Create the app used by the TUI on launch. Reads any saved OpenRouter
    /// key from disk and seeds the welcome document.
    pub fn new() -> Self {
        let working_dir = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
        let mut app = Self::empty();
        app.document = vec![
            Line::from(Span::styled("Condukt", THEME.title())),
            Line::from("A coding agent"),
            Line::from(""),
        ];
        match OpenRouterInferenceProvider::from_saved_key() {
            Ok(Some(provider)) => {
                app.session = Some(Arc::new(Mutex::new(Session::with_system_prompt(
                    provider,
                    CODING_AGENT_PROMPT,
                ))));
            }
            Ok(None) => {}
            Err(error) => app.push_error(format!(
                "Could not restore the saved OpenRouter connection: {error}. Run /connect to sign in again."
            )),
        }
        if app.session.is_none() {
            app.document.push(
                RichText::new()
                    .push_str("Type ")
                    .push_command("/connect")
                    .push_str(" to connect your account.")
                    .into_line(),
            );
        }
        app.footer = Footer::new(working_dir);
        app
    }

    /// Create a bare app with no filesystem access. Used by tests so they
    /// can run in parallel without touching the user's config.
    pub fn empty() -> Self {
        let tools = Arc::new(LocalToolSet::new(PathBuf::from(".")));
        Self {
            session: None,
            input: String::new(),
            document: Vec::new(),
            mode: AppMode::Normal,
            show_commands: false,
            slash_selected: None,
            should_exit: false,
            pending: false,
            footer: Footer::inert(PathBuf::from(".")),
            browser: Box::new(SystemBrowser),
            tools,
            event_rx: None,
            connection_rx: None,
            connection_cancelled: None,
            connection_worker: None,
            pending_started_at: None,
            user_name: system_user_name(),
            model_name: OpenRouterInferenceProvider::new("")
                .model_name()
                .to_string(),
            document_scroll_from_bottom: 0,
        }
    }

    /// Install a pre-populated event receiver and mark the app as
    /// pending. Test-only hook that lets us exercise `poll_agent`
    /// without spinning up a real worker thread.
    #[cfg(test)]
    pub(crate) fn install_event_receiver(&mut self, rx: mpsc::Receiver<AgentMessage>) {
        self.event_rx = Some(rx);
        self.pending = true;
        self.pending_started_at = Some(Instant::now());
    }

    /// Swap the browser opener. Mainly useful in tests.
    #[cfg(test)]
    pub fn with_browser(mut self, browser: Box<dyn BrowserOpener>) -> Self {
        self.browser = browser;
        self
    }

    /// Handle a text submission (Enter pressed without a menu active). The
    /// slash-menu path is handled by `confirm` instead.
    pub fn submit(&mut self) {
        let input = std::mem::take(&mut self.input);
        self.show_commands = false;
        self.slash_selected = None;
        match self.mode.clone() {
            AppMode::Normal => self.submit_normal(&input),
            AppMode::AwaitingApiKey {
                provider,
                opened_browser,
            } => {
                self.submit_api_key(&provider, opened_browser, &input);
            }
            // The selection menus never reach this path; they go through
            // `confirm` -> `confirm_menu`.
            AppMode::AwaitingConnectMethod { .. } | AppMode::AwaitingProvider { .. } => {}
            AppMode::Connecting => {}
        }
    }

    fn submit_normal(&mut self, input: &str) {
        let trimmed = input.trim();
        match trimmed {
            "" => {}
            command if command.starts_with('/') => self.submit_slash_command(command),
            prompt => {
                if self.pending {
                    // A request is in flight; ignore additional submits
                    // so the conversation thread stays coherent.
                    return;
                }
                if self.session.is_none() {
                    self.push_error(
                        "You are not connected. Run /connect to sign in before sending a prompt.",
                    );
                } else {
                    self.push_prompt_echo(prompt);
                    self.send_prompt(prompt);
                }
            }
        }
    }

    fn submit_slash_command(&mut self, input: &str) {
        let Some(command) = parse_slash_command(input) else {
            self.push_error(format!("Unknown command: {input}"));
            return;
        };
        match command.definition.kind {
            SlashCommandKind::Quit => self.should_exit = true,
            SlashCommandKind::Help => self.document.push(Line::from(help_text())),
            SlashCommandKind::Connect => {
                if self.session.is_some() {
                    self.push_info("OpenRouter is already connected.");
                } else if self.connection_rx.is_some() {
                    self.push_info("A previous connection attempt is still finishing.");
                } else {
                    self.enter_connect_method();
                }
            }
            SlashCommandKind::Files => self.list_workspace_files(),
            SlashCommandKind::Read => {
                if command.argument.is_empty() {
                    self.push_error(format!("Usage: {}", command.definition.usage));
                } else {
                    self.read_workspace_file(command.argument);
                }
            }
        }
    }

    fn list_workspace_files(&mut self) {
        match workspace_files(&PathBuf::from(".")) {
            Ok(files) => {
                for file in files {
                    self.document.push(Line::from(file.display().to_string()));
                }
            }
            Err(error) => self.push_error(format!("Could not list files: {error}")),
        }
    }

    fn read_workspace_file(&mut self, path: &str) {
        let arguments = serde_json::json!({ "path": path }).to_string();
        match self.tools.execute("read", &arguments) {
            Ok(contents) => self.document.push(Line::from(contents)),
            Err(error) => self.push_error(error),
        }
    }

    /// Hand the prompt off to a worker thread and stream events back
    /// through a channel. The TUI stays responsive while the request
    /// is in flight; `poll_agent` is called once per frame to apply
    /// whatever the worker has produced so far.
    fn send_prompt(&mut self, prompt: &str) {
        if self.pending {
            // A request is already running. Ignore the new prompt so we
            // don't lose the current conversation thread.
            return;
        }
        let Some(session) = self.session.as_ref().cloned() else {
            unreachable!("send_prompt is only called when a session exists")
        };
        let tools = Arc::clone(&self.tools);
        let prompt = prompt.to_string();
        let (tx, rx) = mpsc::channel();
        self.event_rx = Some(rx);
        self.pending = true;
        self.pending_started_at = Some(Instant::now());
        std::thread::spawn(move || {
            let mut session = session.lock().expect("session mutex poisoned");
            let result = session.submit_with_tools(
                prompt,
                tools.definitions(),
                tools.as_ref(),
                &mut |event| {
                    let _ = tx.send(AgentMessage::Event(event));
                },
            );
            let _ = tx.send(AgentMessage::Done(result));
        });
    }

    pub fn poll_background(&mut self) {
        self.poll_connection();
        self.poll_agent();
    }

    /// Drain any pending events from the agent worker thread. Called
    /// once per frame so the TUI shows streamed output as it arrives.
    /// Returns true while a request is still in flight (so the caller
    /// can keep the prompt dimmed and ignore extra Enter presses).
    pub fn poll_agent(&mut self) -> bool {
        // Collect every message currently buffered, then drop the
        // receiver borrow before mutating `self`. The receiver only
        // borrows immutably and the messages are owned, so we can
        // move them out of the closure.
        let messages: Vec<AgentMessage> = match self.event_rx.as_ref() {
            Some(rx) => std::iter::from_fn(|| rx.try_recv().ok()).collect(),
            None => return false,
        };
        if messages.is_empty() {
            return self.pending;
        }
        for message in messages {
            match message {
                AgentMessage::Event(event) => self.handle_agent_event(event),
                AgentMessage::Done(result) => {
                    self.pending = false;
                    self.event_rx = None;
                    self.pending_started_at = None;
                    if let Err(error) = result {
                        self.push_error(format!("Request failed: {error}"));
                    }
                    return false;
                }
            }
        }
        self.pending
    }

    pub fn pending_elapsed(&self) -> Duration {
        self.pending_started_at
            .map(|started_at| started_at.elapsed())
            .unwrap_or_default()
    }
}

impl Default for App {
    fn default() -> Self {
        Self::empty()
    }
}

/// One message from the agent worker thread. Either an incremental
/// event (text/tool call/tool result) or the final outcome of the
/// request. `pub(crate)` so the test-only hook on `App` that installs
/// a fake receiver can name the type without exposing it to the
/// rest of the crate as a public API.
#[derive(Debug)]
pub(crate) enum AgentMessage {
    Event(AgentEvent),
    Done(Result<Message, InferenceError>),
}

type ConnectionResult = Result<OpenRouterInferenceProvider, String>;

fn system_user_name() -> String {
    std::env::var("USER")
        .or_else(|_| std::env::var("USERNAME"))
        .unwrap_or_else(|_| "You".to_string())
}

mod connection_flow;
mod navigation;
mod transcript;

#[cfg(test)]
use transcript::{tool_call_line, tool_result_line};

#[cfg(test)]
mod tests;
