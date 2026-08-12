use super::*;

// -- Prompt prefix -------------------------------------------------------

#[test]
fn prompt_prefix_changes_with_mode() {
    let (mut app, _recorder) = app_with_recorder();
    assert_eq!(app.prompt_prefix(), "> ");
    app.mode = AppMode::AwaitingApiKey {
        provider: "openrouter".into(),
        opened_browser: false,
    };
    assert_eq!(app.prompt_prefix(), "OpenRouter API key: ");
    app.mode = AppMode::AwaitingConnectMethod { selected: 0 };
    assert_eq!(app.prompt_prefix(), "");
}

#[test]
fn prompt_prefix_shows_in_flight_marker_while_pending() {
    let mut app = test_app();
    assert_eq!(app.prompt_prefix(), "> ");
    app.pending = true;
    // The pending flag wins over the mode so the input visibly pauses
    // while a response is in flight, even inside the key prompt.
    assert!(
        app.prompt_prefix().contains('\u{2026}'),
        "got {:?}",
        app.prompt_prefix()
    );
    app.pending = false;
    app.mode = AppMode::AwaitingApiKey {
        provider: "openrouter".into(),
        opened_browser: false,
    };
    assert_eq!(app.prompt_prefix(), "OpenRouter API key: ");
}

#[test]
fn slash_menu_lines_align_the_description_column() {
    let mut app = test_app();
    app.input = "/".into();
    app.recompute_show_commands();
    let lines = app.slash_menu_lines();
    // The description starts at the same column for every entry: the
    // 2-char prefix ("→ " or "  "), then '/', then the 10-char padded
    // command name. That makes the description column index 13.
    const DESCRIPTION_COLUMN: usize = 13;
    for line in &lines {
        let s = line.to_string();
        let chars: Vec<char> = s.chars().collect();
        assert!(
            chars.len() > DESCRIPTION_COLUMN,
            "line is too short to contain a description: {s:?}"
        );
        assert!(
            chars[DESCRIPTION_COLUMN] != ' ',
            "description should start at column {DESCRIPTION_COLUMN}, got {s:?}"
        );
    }
    // Every line should share the same description column.
    let columns: Vec<usize> = lines
        .iter()
        .map(|line| {
            let s = line.to_string();
            s.chars()
                .nth(DESCRIPTION_COLUMN)
                .map(|c| c.len_utf8())
                .unwrap_or(0)
        })
        .collect();
    let first = columns[0];
    assert!(
        columns.iter().all(|c| *c == first),
        "description columns should all match, got {columns:?}"
    );
}

#[test]
fn slash_menu_lines_bold_the_selected_entry() {
    let mut app = test_app();
    app.input = "/".into();
    app.recompute_show_commands();
    let lines = app.slash_menu_lines();
    // The line's overall style is applied to every span during
    // rendering, so we assert there. The selected entry bolds the
    // whole row; the unselected rows stay plain.
    let selected = &lines[0];
    assert!(
        selected.style.add_modifier.contains(Modifier::BOLD),
        "selected entry should be bold: {selected:?}"
    );
    for line in &lines[1..] {
        assert!(
            !line.style.add_modifier.contains(Modifier::BOLD),
            "unselected entry should not be bold: {line:?}"
        );
    }
}

// -- Async agent event loop -------------------------------------------

fn build_test_session() -> Arc<Mutex<Session<OpenRouterInferenceProvider>>> {
    // The real OpenRouter key is not read here; we only need a
    // session handle for tests that exercise the event channel.
    Arc::new(Mutex::new(Session::new(OpenRouterInferenceProvider::new(
        "sk-or-v1-test",
    ))))
}

#[test]
fn submit_prompt_starts_the_border_progress_animation() {
    let mut app = test_app();
    app.session = Some(build_test_session());
    let docs_before = app.document.len();
    app.input = "hello".into();
    app.submit();
    assert!(app.pending, "submit should mark the app as pending");
    assert_eq!(
        app.document.len(),
        docs_before + 2,
        "submit should only push the prompt message block, got {:?}",
        app.document.iter().map(Line::to_string).collect::<Vec<_>>()
    );
    assert!(
        app.pending_started_at.is_some(),
        "a pending request should start the progress animation"
    );
}

#[test]
fn submit_normal_ignores_extra_prompts_while_pending() {
    let mut app = test_app();
    app.session = Some(build_test_session());
    app.input = "first".into();
    app.submit();
    assert!(app.pending);
    let docs_after_first = app.document.len();
    let input_before = app.input.clone();
    app.input = "second".into();
    app.submit();
    // The second submit clears the input (so the user can start
    // typing their next message) but the catch-all in
    // `submit_normal` short-circuits, so no second echo or
    // timeline entry lands in the document.
    assert_eq!(app.input, "", "input should be cleared on submit");
    assert_eq!(
        app.document.len(),
        docs_after_first,
        "second submit while pending should not push any lines (had {input_before:?})"
    );
}

#[test]
fn poll_agent_returns_false_when_nothing_is_in_flight() {
    let mut app = test_app();
    assert!(!app.poll_agent());
}

#[test]
fn poll_agent_drains_events_and_clears_pending_on_done() {
    let mut app = test_app();
    let (tx, rx) = mpsc::channel();
    app.install_event_receiver(rx);
    tx.send(AgentMessage::Event(AgentEvent::Text("hello there".into())))
        .unwrap();
    tx.send(AgentMessage::Done(Ok(Message::assistant("world"))))
        .unwrap();
    let in_flight = app.poll_agent();
    assert!(!in_flight, "Done should clear pending");
    assert!(!app.pending);
    let texts: Vec<String> = app
        .document
        .iter()
        .map(Line::to_string)
        .filter(|line| !line.trim().is_empty())
        .collect();
    assert!(
        texts.iter().any(|line| line.ends_with("hello there")),
        "text event should land in the document, got {texts:?}"
    );
}

#[test]
fn poll_agent_reports_request_failure() {
    let mut app = test_app();
    let (tx, rx) = mpsc::channel();
    app.install_event_receiver(rx);
    tx.send(AgentMessage::Done(Err(InferenceError::Request(
        "boom".into(),
    ))))
    .unwrap();
    let in_flight = app.poll_agent();
    assert!(!in_flight);
    let last = app
        .document
        .last()
        .expect("a failure message was pushed")
        .to_string();
    assert!(
        last.contains("Request failed") && last.contains("boom"),
        "expected a Request failed line, got {last:?}"
    );
}
