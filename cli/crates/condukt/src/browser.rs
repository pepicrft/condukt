//! Abstraction over "open this URL in the user's browser".
//!
//! Wrapping the `open` crate in a trait keeps the real side effect out of
//! the type system so unit tests can swap in a recorder without spawning
//! processes.

use std::fmt::Debug;

pub trait BrowserOpener: Debug + Send {
    fn open(&self, url: &str);
}

#[derive(Debug)]
pub struct SystemBrowser;

impl BrowserOpener for SystemBrowser {
    fn open(&self, url: &str) {
        // The crate surfaces a `Result` we cannot meaningfully act on from a
        // TUI; the user already sees the URL inline, so a silent failure is
        // the right user experience.
        let _ = open::that(url);
    }
}
