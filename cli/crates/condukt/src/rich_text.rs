//! Rich text with semantic annotations.
//!
//! A `RichText` is a sequence of `RichSpan`s, each carrying a `SpanKind`
//! that the renderer maps to a `Style`. This lets the caller express
//! semantic intent ("this is a command", "this is a file path") without
//! hard-coding colors, and lets the renderer decide how to style each
//! kind.

use ratatui::{
    style::Style,
    text::{Line, Span},
};

use crate::theme::THEME;

/// One annotated chunk of text.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RichSpan {
    text: String,
    kind: SpanKind,
}

/// Semantic kinds of inline text. The renderer maps each kind to a
/// `Style` so the source can stay neutral about colors.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SpanKind {
    Text,
    Command,
}

impl RichSpan {
    pub fn text(text: impl Into<String>) -> Self {
        Self {
            text: text.into(),
            kind: SpanKind::Text,
        }
    }

    pub fn command(text: impl Into<String>) -> Self {
        Self {
            text: text.into(),
            kind: SpanKind::Command,
        }
    }

    pub fn style(&self) -> Style {
        match self.kind {
            SpanKind::Text => Style::default(),
            // Plain cyan so the command reads as a verb in the menu
            // without the bold modifier pushing the selected entry into
            // the terminal's "bright" palette (which renders as white).
            SpanKind::Command => THEME.accent_text(),
        }
    }
}

#[derive(Clone, Debug, Default)]
pub struct RichText {
    spans: Vec<RichSpan>,
}

impl RichText {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn push(mut self, span: RichSpan) -> Self {
        self.spans.push(span);
        self
    }

    pub fn push_str(self, text: impl Into<String>) -> Self {
        self.push(RichSpan::text(text))
    }

    pub fn push_command(self, text: impl Into<String>) -> Self {
        self.push(RichSpan::command(text))
    }

    pub fn into_line(self) -> Line<'static> {
        let spans: Vec<Span<'static>> = self
            .spans
            .into_iter()
            .map(|span| {
                let style = span.style();
                Span::styled(span.text, style)
            })
            .collect();
        Line::from(spans)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ratatui::style::Modifier;

    #[test]
    fn empty_rich_text_renders_to_an_empty_line() {
        let line: Line<'static> = RichText::new().into_line();
        assert!(line.spans.is_empty());
    }

    #[test]
    fn command_spans_use_the_command_style() {
        let rich = RichText::new()
            .push_str("Type ")
            .push_command("/connect")
            .push_str(" to connect.")
            .into_line();
        assert_eq!(rich.spans.len(), 3);
        assert_eq!(rich.spans[1].content.as_ref(), "/connect");
        assert_eq!(rich.spans[1].style.fg, Some(THEME.colors.accent));
        // The command style is plain cyan so the selected slash-menu
        // entry does not flash white through the terminal's bright
        // palette.
        assert!(!rich.spans[1].style.add_modifier.contains(Modifier::BOLD));
    }
}
