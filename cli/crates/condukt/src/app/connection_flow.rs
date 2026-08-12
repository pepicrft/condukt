use super::*;

impl App {
    pub(super) fn submit_api_key(&mut self, provider: &str, opened_browser: bool, input: &str) {
        let key = input.trim();
        if key.is_empty() {
            self.push_error("API key cannot be empty. Press Esc to cancel.");
            return;
        }
        self.begin_key_connection(provider, opened_browser, key);
    }

    pub(super) fn enter_connect_method(&mut self) {
        self.document.push(Line::from(""));
        self.document
            .push(Line::from("Let's connect your account."));
        self.mode = AppMode::AwaitingConnectMethod { selected: 0 };
    }

    pub(super) fn enter_provider(&mut self) {
        self.mode = AppMode::AwaitingProvider { selected: 0 };
    }

    /// Move into the API-key input mode. If `opened_browser` is true, the
    /// host browser is opened to the provider's key page so the user can
    /// create or copy a key without leaving the agent.
    pub(super) fn begin_api_key_input(&mut self, provider: &str, opened_browser: bool) {
        if opened_browser && let Some(url) = provider_keys_url(provider) {
            self.browser.open(url);
            self.document.push(Line::from(""));
            self.document.push(Line::from(format!(
                "Opening {url} in your browser. Create or copy a key there, then paste it below."
            )));
        }
        self.document.push(Line::from(""));
        self.push_info("Paste your API key below. Press Esc to cancel.");
        self.mode = AppMode::AwaitingApiKey {
            provider: provider.to_string(),
            opened_browser,
        };
    }

    fn begin_key_connection(&mut self, provider: &str, _opened_browser: bool, key: &str) {
        if !provider.eq_ignore_ascii_case("openrouter") {
            self.push_error(format!("Unknown provider: {provider}"));
            self.mode = AppMode::Normal;
            return;
        }
        let key = key.to_string();
        self.start_connection_worker(move |cancelled| connection::connect_with_key(key, cancelled));
    }

    /// Run the OpenRouter OAuth flow: open the authorize URL in the host
    /// browser, wait for the loopback callback, exchange the code for a
    /// permanent API key, and save it. On failure, fall back to a normal
    /// prompt with an error message so the user is not stuck.
    pub(super) fn begin_oauth_flow(&mut self, provider: &str) {
        if !provider.eq_ignore_ascii_case("openrouter") {
            self.push_error(format!("Unknown provider: {provider}"));
            self.mode = AppMode::Normal;
            return;
        }
        match oauth_flow::start_login() {
            Ok(login) => {
                self.browser.open(login.authorize_url());
                self.push_info("Complete sign-in in your browser. Press Esc to cancel.");
                self.start_connection_worker(move |cancelled| {
                    connection::complete_browser_login(login, cancelled)
                });
            }
            Err(error) => {
                self.push_error(format!("OpenRouter sign-in failed: {error}"));
                self.mode = AppMode::Normal;
            }
        }
    }

    fn start_connection_worker(
        &mut self,
        connect: impl FnOnce(&AtomicBool) -> ConnectionResult + Send + 'static,
    ) {
        let cancelled = Arc::new(AtomicBool::new(false));
        let worker_cancelled = Arc::clone(&cancelled);
        let (sender, receiver) = mpsc::channel();
        let worker = std::thread::spawn(move || {
            let result = connect(&worker_cancelled);
            let _ = sender.send(result);
        });
        self.mode = AppMode::Connecting;
        self.connection_rx = Some(receiver);
        self.connection_cancelled = Some(cancelled);
        self.connection_worker = Some(worker);
        self.pending_started_at = Some(Instant::now());
    }

    pub fn cancel_connection(&mut self) -> bool {
        if !self.is_connecting() {
            return false;
        }
        if let Some(cancelled) = &self.connection_cancelled {
            cancelled.store(true, Ordering::Release);
        }
        self.mode = AppMode::Normal;
        self.pending_started_at = None;
        self.push_info("Connection cancelled.");
        true
    }

    pub(super) fn poll_connection(&mut self) {
        let message = match self.connection_rx.as_ref() {
            Some(receiver) => match receiver.try_recv() {
                Ok(result) => Some(result),
                Err(mpsc::TryRecvError::Empty) => None,
                Err(mpsc::TryRecvError::Disconnected) => {
                    Some(Err("Connection worker stopped unexpectedly".to_string()))
                }
            },
            None => None,
        };
        let Some(result) = message else {
            return;
        };
        let was_cancelled = self
            .connection_cancelled
            .as_ref()
            .is_some_and(|cancelled| cancelled.load(Ordering::Acquire));
        self.connection_rx = None;
        self.connection_cancelled = None;
        if let Some(worker) = self.connection_worker.take() {
            let _ = worker.join();
        }
        if !self.pending {
            self.pending_started_at = None;
        }
        self.mode = AppMode::Normal;
        if was_cancelled {
            return;
        }
        match result {
            Ok(provider) => {
                self.session = Some(Arc::new(Mutex::new(Session::with_system_prompt(
                    provider,
                    CODING_AGENT_PROMPT,
                ))));
                self.document.push(Line::from(Span::styled(
                    "OpenRouter connected.",
                    THEME.accent_text(),
                )));
            }
            Err(error) => {
                self.push_error(error);
                self.push_info("Run /connect to try again.");
            }
        }
    }
}

/// URL to the provider's page where the user can create or copy an API key.
/// None means we do not know how to guide the user for that provider yet.
fn provider_keys_url(provider: &str) -> Option<&'static str> {
    match provider.to_ascii_lowercase().as_str() {
        "openrouter" => Some("https://openrouter.ai/keys"),
        _ => None,
    }
}
