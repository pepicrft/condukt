use super::*;
use crate::commands::{SLASH_COMMANDS, filter_slash_commands};

fn test_app() -> App {
    App::empty()
}

fn app_with_recorder() -> (App, std::sync::Arc<RecordingBrowserInner>) {
    let recorder = std::sync::Arc::new(RecordingBrowserInner::default());
    let boxed: Box<dyn BrowserOpener> = Box::new(RecordingBrowserAdapter {
        inner: recorder.clone(),
    });
    let app = App::empty().with_browser(boxed);
    (app, recorder)
}

#[derive(Default)]
struct RecordingBrowserInner {
    opened: std::sync::Mutex<Vec<String>>,
}

struct RecordingBrowserAdapter {
    inner: std::sync::Arc<RecordingBrowserInner>,
}

impl std::fmt::Debug for RecordingBrowserAdapter {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("RecordingBrowserAdapter").finish()
    }
}

impl BrowserOpener for RecordingBrowserAdapter {
    fn open(&self, url: &str) {
        self.inner
            .opened
            .lock()
            .expect("recorder mutex")
            .push(url.to_string());
    }
}

mod commands_and_modes;
mod presentation_and_workers;
