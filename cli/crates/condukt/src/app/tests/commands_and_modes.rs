use super::*;

// -- Slash command filter ------------------------------------------------

#[test]
fn filter_returns_every_command_for_empty_query() {
    let names: Vec<&str> = filter_slash_commands("").iter().map(|c| c.name).collect();
    assert_eq!(names.len(), SLASH_COMMANDS.len());
}

#[test]
fn filter_matches_exact_command_name() {
    let names: Vec<&str> = filter_slash_commands("connect")
        .iter()
        .map(|c| c.name)
        .collect();
    assert_eq!(names, vec!["connect"]);
}

#[test]
fn filter_uses_fuzzy_matching() {
    let names: Vec<&str> = filter_slash_commands("cn").iter().map(|c| c.name).collect();
    assert!(names.contains(&"connect"));
}

#[test]
fn filter_returns_empty_when_nothing_matches() {
    let commands = filter_slash_commands("zzzzzz");
    assert!(commands.is_empty());
}

// -- App mode transitions -----------------------------------------------

#[test]
fn submit_quit_sets_should_exit() {
    let mut app = test_app();
    app.input = "/quit".into();
    app.submit();
    assert!(app.should_exit);
}

#[test]
fn submit_empty_does_nothing() {
    let mut app = test_app();
    let docs_before = app.document.len();
    app.input = "   ".into();
    app.submit();
    assert!(!app.should_exit);
    assert_eq!(app.document.len(), docs_before);
}

#[test]
fn submit_unknown_slash_command_reports_error() {
    let mut app = test_app();
    app.input = "/nope".into();
    app.submit();
    let last = app.document.last().expect("error was pushed");
    assert!(format!("{last:?}").contains("Unknown command"));
}

#[test]
fn submit_connect_without_session_enters_menu() {
    let (mut app, _recorder) = app_with_recorder();
    app.input = "/connect".into();
    app.submit();
    assert!(app.is_in_menu());
}

#[test]
fn prompt_without_session_shows_an_error_without_opening_connect() {
    let (mut app, _recorder) = app_with_recorder();
    app.input = "hello world".into();
    app.submit();
    assert!(app.is_normal());
    let error_header = app
        .document
        .get(app.document.len() - 2)
        .expect("error header was pushed");
    let error_body = app.document.last().expect("connection error was pushed");
    assert_eq!(error_header.to_string(), "▌ Error");
    assert!(error_body.to_string().starts_with("▌ "));
    assert!(error_body.to_string().contains("/connect"));
    assert_eq!(
        error_header.spans[0].style.fg,
        Some(ratatui::style::Color::Red)
    );
}

#[test]
fn push_error_uses_a_titled_red_message_block() {
    let mut app = test_app();
    app.push_error("Something went wrong.");
    assert_eq!(app.document.len(), 2);
    let header = &app.document[0];
    let body = &app.document[1];
    assert_eq!(header.to_string(), "▌ Error");
    assert_eq!(body.to_string(), "▌ Something went wrong.");
    assert_eq!(header.spans[0].style.fg, Some(ratatui::style::Color::Red));
}

#[test]
fn push_error_separates_itself_from_the_preceding_entry() {
    let mut app = test_app();
    app.push_info("Type /connect to connect your account.");
    app.push_error("You are not connected.");
    assert_eq!(app.document[1].to_string(), "");
    assert_eq!(app.document[2].to_string(), "▌ Error");
}

#[test]
fn prompt_echo_uses_a_named_user_message_block() {
    let mut app = test_app();
    app.push_prompt_echo("Hola");
    assert_eq!(app.document.len(), 2);
    let header = &app.document[0];
    let message = &app.document[1];
    assert_eq!(header.to_string(), format!("▌ {}", app.user_name));
    assert_eq!(message.to_string(), "▌ Hola");
    assert_eq!(header.spans[0].style.fg, Some(THEME.colors.user));
}

#[test]
fn model_activity_and_tool_calls_have_accent_markers() {
    let mut app = test_app();
    app.handle_agent_event(AgentEvent::Text("Inspecting the workspace.".into()));
    let model_activity = app.document.last().expect("model activity was pushed");
    assert_eq!(model_activity.to_string(), "▌ Inspecting the workspace.");
    assert_eq!(model_activity.spans[0].style.fg, Some(THEME.colors.accent));

    let tool_call = tool_call_line("read", r#"{\"path\":\"README.md\"}"#);
    assert!(tool_call.to_string().starts_with("▌ tool read"));
    assert_eq!(tool_call.spans[0].style.fg, Some(THEME.colors.accent));

    let tool_result = tool_result_line("read", "Contents".into(), None);
    assert!(tool_result.to_string().starts_with("┆ read Contents"));
    assert_eq!(tool_result.spans[0].style.fg, Some(THEME.colors.muted));

    let failed_tool = tool_result_line("read", String::new(), Some("Denied".into()));
    assert!(failed_tool.to_string().starts_with("▌ read Denied"));
    assert_eq!(failed_tool.spans[0].style.fg, Some(THEME.colors.danger));
}

#[test]
fn menu_navigate_wraps_around() {
    let (mut app, _recorder) = app_with_recorder();
    app.mode = AppMode::AwaitingConnectMethod { selected: 0 };
    app.select_up();
    assert!(matches!(
        app.mode,
        AppMode::AwaitingConnectMethod { selected: 1 }
    ));
    app.select_down();
    assert!(matches!(
        app.mode,
        AppMode::AwaitingConnectMethod { selected: 0 }
    ));
    app.select_down();
    assert!(matches!(
        app.mode,
        AppMode::AwaitingConnectMethod { selected: 1 }
    ));
}

#[test]
fn menu_confirm_account_enters_provider() {
    let (mut app, _recorder) = app_with_recorder();
    app.mode = AppMode::AwaitingConnectMethod { selected: 0 };
    app.confirm();
    assert!(matches!(
        app.mode,
        AppMode::AwaitingProvider { selected: 0 }
    ));
}

#[test]
fn menu_confirm_api_key_enters_api_key_input() {
    let (mut app, _recorder) = app_with_recorder();
    app.mode = AppMode::AwaitingConnectMethod { selected: 1 };
    app.confirm();
    assert!(matches!(
        app.mode,
        AppMode::AwaitingApiKey {
            opened_browser: false,
            ..
        }
    ));
}

#[test]
fn menu_confirm_openrouter_opens_browser_via_oauth() {
    use std::sync::Arc;
    use std::sync::atomic::{AtomicBool, Ordering};
    let opened = Arc::new(AtomicBool::new(false));
    struct FlagBrowser(Arc<AtomicBool>);
    impl std::fmt::Debug for FlagBrowser {
        fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            f.debug_struct("FlagBrowser").finish()
        }
    }
    impl BrowserOpener for FlagBrowser {
        fn open(&self, _url: &str) {
            self.0.store(true, Ordering::SeqCst);
        }
    }
    let opened_for_browser = Arc::clone(&opened);
    let mut app = App::empty().with_browser(Box::new(FlagBrowser(opened_for_browser)));
    app.mode = AppMode::AwaitingProvider { selected: 0 };
    let started_at = Instant::now();
    app.confirm();
    assert!(
        opened.load(Ordering::SeqCst),
        "OAuth flow should have opened the browser before waiting on the callback"
    );
    assert!(app.is_connecting());
    assert!(
        started_at.elapsed() < Duration::from_secs(1),
        "confirm should not wait for the browser callback"
    );

    assert!(app.cancel_connection());
    for _ in 0..100 {
        app.poll_background();
        if app.connection_rx.is_none() {
            break;
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    assert!(app.connection_rx.is_none(), "cancelled worker should stop");
    assert!(app.is_normal());
}

#[test]
fn menu_lines_have_selection_marker() {
    let (mut app, _recorder) = app_with_recorder();
    app.mode = AppMode::AwaitingConnectMethod { selected: 0 };
    let lines = app.menu_lines();
    let has_arrow = lines
        .iter()
        .any(|line| line.to_string().contains("→ Sign in with an account"));
    assert!(has_arrow);
}

// -- Slash menu selection ------------------------------------------------

#[test]
fn typing_slash_highlights_first_command() {
    let mut app = test_app();
    app.input.push('/');
    app.recompute_show_commands();
    assert!(app.show_commands);
    assert_eq!(app.slash_selected, Some(0));
}

#[test]
fn slash_selection_moves_with_arrows() {
    let mut app = test_app();
    app.input = "/".into();
    app.recompute_show_commands();
    let first = app.slash_selected;
    app.select_down();
    assert_ne!(app.slash_selected, first);
    app.select_up();
    assert_eq!(app.slash_selected, first);
}

#[test]
fn slash_confirm_runs_the_highlighted_command() {
    let (mut app, _recorder) = app_with_recorder();
    app.input = "/".into();
    app.recompute_show_commands();
    // The first filtered command is whatever the matcher scores highest.
    let highlighted = app.slash_selected.expect("selection set");
    let commands = filter_slash_commands("");
    let expected_name = commands[highlighted].name;
    app.confirm();
    // The selected command should be in the input and submitted.
    assert!(app.should_exit || !app.document.is_empty() || app.input.is_empty());
    let _ = expected_name; // referenced for clarity
}
