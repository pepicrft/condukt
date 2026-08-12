use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};

use crate::app::{App, AppMode};

/// Returns true if the app should keep running, false if the user asked to quit.
pub fn handle_key(app: &mut App, key: KeyEvent) -> bool {
    if key.code == KeyCode::Char('c') && key.modifiers.contains(KeyModifiers::CONTROL) {
        return handle_ctrl_c(app);
    }
    if key.code == KeyCode::Esc {
        return handle_escape(app);
    }
    if app.is_busy()
        && matches!(
            key.code,
            KeyCode::Up | KeyCode::Down | KeyCode::Char(_) | KeyCode::Backspace | KeyCode::Enter
        )
    {
        return true;
    }
    match key.code {
        KeyCode::Up => app.select_up(),
        KeyCode::Down => app.select_down(),
        KeyCode::Char(character) => {
            app.input.push(character);
            app.recompute_show_commands();
        }
        KeyCode::Backspace => {
            app.input.pop();
            app.recompute_show_commands();
        }
        KeyCode::Enter => app.confirm(),
        KeyCode::PageUp => app.scroll_document_up(),
        KeyCode::PageDown => app.scroll_document_down(),
        _ => {}
    }
    true
}

/// Esc clears the input if there is something to clear, cancels an ongoing
/// flow (e.g. the API key prompt or a selection menu), or does nothing
/// otherwise.
fn handle_escape(app: &mut App) -> bool {
    if try_clear_or_cancel(app) {
        return true;
    }
    true
}

/// Ctrl+C behaves like Esc when there is something to clear or an ongoing
/// flow, and only exits when there is nothing pending.
fn handle_ctrl_c(app: &mut App) -> bool {
    if try_clear_or_cancel(app) {
        return true;
    }
    false
}

/// Clear the input, cancel an ongoing flow, or do nothing. Returns `true`
/// if it performed an action, `false` if there was nothing to do.
fn try_clear_or_cancel(app: &mut App) -> bool {
    if !app.input.is_empty() {
        app.input.clear();
        app.show_commands = false;
        app.slash_selected = None;
        return true;
    }
    if app.cancel_connection() {
        return true;
    }
    if app.is_in_menu() {
        app.mode = AppMode::Normal;
        app.push_info("Cancelled.");
        return true;
    }
    if matches!(app.mode, AppMode::AwaitingApiKey { .. }) {
        app.mode = AppMode::Normal;
        app.push_info("Connection cancelled.");
        return true;
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;
    use crossterm::event::KeyEvent;

    fn key(code: KeyCode) -> KeyEvent {
        KeyEvent::new(code, KeyModifiers::NONE)
    }

    fn ctrl_c() -> KeyEvent {
        KeyEvent::new(KeyCode::Char('c'), KeyModifiers::CONTROL)
    }

    fn app_with_input(text: &str) -> App {
        let mut app = App::empty();
        app.input = text.into();
        app
    }

    // -- Esc ----------------------------------------------------------------

    #[test]
    fn esc_clears_pending_input() {
        let mut app = app_with_input("hello");
        let keep_running = handle_escape(&mut app);
        assert!(keep_running);
        assert!(app.input.is_empty());
        assert!(!app.show_commands);
        assert!(app.slash_selected.is_none());
    }

    #[test]
    fn esc_cancels_api_key_flow() {
        let mut app = App::empty();
        app.mode = AppMode::AwaitingApiKey {
            provider: "openrouter".into(),
            opened_browser: false,
        };
        let keep_running = handle_escape(&mut app);
        assert!(keep_running);
        assert!(app.is_normal());
        assert!(
            app.document
                .iter()
                .any(|line| format!("{line:?}").contains("Connection cancelled"))
        );
    }

    #[test]
    fn esc_cancels_a_background_connection() {
        let mut app = App::empty();
        app.mode = AppMode::Connecting;
        let keep_running = handle_escape(&mut app);
        assert!(keep_running);
        assert!(app.is_normal());
        assert!(
            app.document
                .last()
                .is_some_and(|line| line.to_string().contains("cancelled"))
        );
    }

    #[test]
    fn esc_cancels_selection_menu() {
        let mut app = App::empty();
        app.mode = AppMode::AwaitingConnectMethod { selected: 0 };
        let keep_running = handle_escape(&mut app);
        assert!(keep_running);
        assert!(app.is_normal());
    }

    #[test]
    fn esc_with_nothing_pending_is_a_noop() {
        let mut app = App::empty();
        let docs_before = app.document.len();
        let keep_running = handle_escape(&mut app);
        assert!(keep_running);
        assert!(app.is_normal());
        assert_eq!(app.document.len(), docs_before);
    }

    // -- Ctrl+C -------------------------------------------------------------

    #[test]
    fn ctrl_c_clears_pending_input_without_quitting() {
        let mut app = app_with_input("hello");
        let keep_running = handle_ctrl_c(&mut app);
        assert!(keep_running);
        assert!(app.input.is_empty());
    }

    #[test]
    fn ctrl_c_cancels_ongoing_flow_without_quitting() {
        let mut app = App::empty();
        app.mode = AppMode::AwaitingProvider { selected: 0 };
        let keep_running = handle_ctrl_c(&mut app);
        assert!(keep_running);
        assert!(app.is_normal());
    }

    #[test]
    fn ctrl_c_with_nothing_pending_quits() {
        let mut app = App::empty();
        let keep_running = handle_ctrl_c(&mut app);
        assert!(!keep_running);
    }

    // -- Routing through handle_key ----------------------------------------

    #[test]
    fn handle_key_up_down_navigate_menu() {
        let mut app = App::empty();
        app.mode = AppMode::AwaitingConnectMethod { selected: 0 };
        handle_key(&mut app, key(KeyCode::Down));
        assert!(matches!(
            app.mode,
            AppMode::AwaitingConnectMethod { selected: 1 }
        ));
        handle_key(&mut app, key(KeyCode::Up));
        assert!(matches!(
            app.mode,
            AppMode::AwaitingConnectMethod { selected: 0 }
        ));
    }

    #[test]
    fn handle_key_routes_escape() {
        let mut app = app_with_input("hi");
        let keep_running = handle_key(&mut app, key(KeyCode::Esc));
        assert!(keep_running);
        assert!(app.input.is_empty());
    }

    #[test]
    fn handle_key_routes_ctrl_c() {
        let mut app = App::empty();
        let keep_running = handle_key(&mut app, ctrl_c());
        assert!(!keep_running);
    }

    #[test]
    fn handle_key_typing_updates_input() {
        let mut app = App::empty();
        handle_key(&mut app, key(KeyCode::Char('h')));
        handle_key(&mut app, key(KeyCode::Char('i')));
        assert_eq!(app.input, "hi");
    }

    #[test]
    fn handle_key_backspace_trims_input() {
        let mut app = app_with_input("hi");
        handle_key(&mut app, key(KeyCode::Backspace));
        assert_eq!(app.input, "h");
    }

    #[test]
    fn page_keys_scroll_the_transcript() {
        let mut app = App::empty();
        app.document = (0..10)
            .map(|index| format!("line {index}").into())
            .collect();
        handle_key(&mut app, key(KeyCode::PageUp));
        assert_eq!(app.document_scroll(2), 5);
        handle_key(&mut app, key(KeyCode::PageDown));
        assert_eq!(app.document_scroll(2), 8);
    }

    #[test]
    fn handle_key_enter_submits() {
        let mut app = app_with_input("/quit");
        let keep_running = handle_key(&mut app, key(KeyCode::Enter));
        assert!(keep_running);
        assert!(app.should_exit);
    }

    #[test]
    fn handle_key_show_commands_toggles_on_slash_prefix() {
        let mut app = App::empty();
        handle_key(&mut app, key(KeyCode::Char('/')));
        assert!(app.show_commands);
        assert_eq!(app.slash_selected, Some(0));
        handle_key(&mut app, key(KeyCode::Char('h')));
        assert!(app.show_commands);
        // Typing a non-matching character hides the menu.
        handle_key(&mut app, key(KeyCode::Char('x')));
        handle_key(&mut app, key(KeyCode::Char('x')));
        assert!(!app.show_commands);
    }
}
