//! Semantic presentation tokens for Condukt's terminal interface.
//!
//! Ratatui renders terminal styles rather than Cascading Style Sheets, so
//! [`Theme`] is the typed equivalent of a web theme's custom properties.
//! Views ask for roles such as `activity_marker` or `muted_text`; they never
//! choose a terminal colour directly.

use ratatui::style::{Color, Modifier, Style};

#[derive(Clone, Copy, Debug)]
pub struct Colors {
    pub text: Color,
    pub muted: Color,
    pub accent: Color,
    pub user: Color,
    pub danger: Color,
    pub border: Color,
}

#[derive(Clone, Copy, Debug)]
pub struct Theme {
    /// Named color scale, following Theme UI's `colors` convention.
    pub colors: Colors,
}

/// Condukt's default dark-terminal palette. The field names are stable,
/// semantic tokens, making an alternate palette a data change rather than a
/// search-and-replace across renderers.
pub const THEME: Theme = Theme {
    colors: Colors {
        text: Color::Gray,
        muted: Color::DarkGray,
        accent: Color::Cyan,
        user: Color::Green,
        danger: Color::Red,
        border: Color::DarkGray,
    },
};

impl Theme {
    pub const fn text(self) -> Style {
        Style::new().fg(self.colors.text)
    }

    pub const fn title(self) -> Style {
        Style::new()
            .fg(self.colors.accent)
            .add_modifier(Modifier::BOLD)
    }

    pub const fn accent_text(self) -> Style {
        Style::new().fg(self.colors.accent)
    }

    pub const fn selected(self) -> Style {
        self.accent_text().add_modifier(Modifier::BOLD)
    }

    pub const fn muted_text(self) -> Style {
        Style::new().fg(self.colors.muted)
    }

    pub const fn muted_italic(self) -> Style {
        self.muted_text().add_modifier(Modifier::ITALIC)
    }

    pub const fn prompt_prefix(self) -> Style {
        self.accent_text().add_modifier(Modifier::BOLD)
    }

    pub const fn border(self) -> Style {
        Style::new().fg(self.colors.border)
    }

    pub const fn user_marker(self) -> Style {
        Style::new().fg(self.colors.user)
    }

    /// A cyan left edge identifies model activity and tool invocations.
    pub const fn activity_marker(self) -> Style {
        self.accent_text()
    }

    pub const fn error_marker(self) -> Style {
        Style::new().fg(self.colors.danger)
    }

    pub const fn error_text(self) -> Style {
        Style::new().fg(self.colors.danger)
    }
}
