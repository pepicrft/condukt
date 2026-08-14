use super::*;
use crate::commands::filter_slash_commands;

impl App {
    pub fn prompt_prefix(&self) -> &'static str {
        if self.is_busy() {
            // While the worker is in flight we show a different
            // prefix so the user knows their Enter was received and
            // something is happening, even before the first event
            // streams in.
            return "… ";
        }
        match self.mode {
            AppMode::Normal => "> ",
            AppMode::AwaitingApiKey { .. } => "OpenRouter API key: ",
            AppMode::Connecting => "… ",
            // The prompt is hidden behind a menu in the selection states.
            AppMode::AwaitingConnectMethod { .. } | AppMode::AwaitingProvider { .. } => "",
        }
    }

    pub fn is_normal(&self) -> bool {
        matches!(self.mode, AppMode::Normal)
    }

    pub fn is_connecting(&self) -> bool {
        matches!(self.mode, AppMode::Connecting)
    }

    pub fn is_busy(&self) -> bool {
        self.pending || self.is_connecting()
    }

    /// True when the TUI is showing a navigable menu instead of the prompt.
    pub fn is_in_menu(&self) -> bool {
        matches!(
            self.mode,
            AppMode::AwaitingConnectMethod { .. } | AppMode::AwaitingProvider { .. }
        )
    }

    pub fn document_lines(&self) -> Vec<Line<'static>> {
        self.document.clone()
    }

    pub fn document_scroll(&self, viewport_height: u16) -> u16 {
        let max_scroll = self
            .document
            .len()
            .saturating_sub(usize::from(viewport_height));
        max_scroll
            .saturating_sub(usize::from(self.document_scroll_from_bottom))
            .min(usize::from(u16::MAX)) as u16
    }

    pub fn scroll_document_up(&mut self) {
        self.document_scroll_from_bottom = self.document_scroll_from_bottom.saturating_add(3);
    }

    pub fn scroll_document_down(&mut self) {
        self.document_scroll_from_bottom = self.document_scroll_from_bottom.saturating_sub(3);
    }

    /// Render the slash-command menu with the currently highlighted entry
    /// marked with a `→` and bold styling.
    pub fn slash_menu_lines(&self) -> Vec<Line<'static>> {
        let query = self.input.trim_start_matches('/');
        filter_slash_commands(query)
            .into_iter()
            .enumerate()
            .map(|(index, command)| {
                let is_selected = self.slash_selected == Some(index);
                let prefix = if is_selected { "→ " } else { "  " };
                // Pad the command name so the description column lines up
                // regardless of which entry is selected.
                let padded_name = format!("{:<10}", command.name);
                // Every row uses the same cyan for the command name and
                // description; the selected row is bolded so the arrow is
                // the only thing that changes. `patch_style` overwrites
                // modifiers rather than merging them, so the colour must
                // be applied first and the bold second.
                let mut line = RichText::new()
                    .push_str(prefix)
                    .push_str("/")
                    .push_command(padded_name)
                    .push_str(command.description)
                    .into_line();
                line = line.patch_style(THEME.accent_text());
                if is_selected {
                    line = line.patch_style(Style::default().add_modifier(Modifier::BOLD));
                }
                line
            })
            .collect()
    }

    /// The number of terminal rows needed to render the current selection
    /// menu, including its top/bottom borders. Zero when no menu is shown.
    pub fn menu_height(&self) -> u16 {
        let question = self.menu_question().is_some() as u16;
        let options = self.menu_options().map_or(0, |o| o.len() as u16);
        // 1 header + 1 spacer + N options + 1 spacer + 1 hints + 2 borders
        question + 1 + options + 1 + 1 + 2
    }

    /// Render the active selection menu (connect method or provider).
    pub fn menu_lines(&self) -> Vec<Line<'static>> {
        let Some(question) = self.menu_question() else {
            return Vec::new();
        };
        let Some(options) = self.menu_options() else {
            return Vec::new();
        };
        let selected = match self.mode {
            AppMode::AwaitingConnectMethod { selected } => selected,
            AppMode::AwaitingProvider { selected } => selected,
            _ => 0,
        };
        let mut lines = vec![
            Line::from(Span::styled(
                question,
                Style::default().add_modifier(Modifier::BOLD),
            )),
            Line::from(""),
        ];
        for (index, option) in options.iter().enumerate() {
            let prefix = if index == selected { "→ " } else { "  " };
            let style = if index == selected {
                THEME.selected()
            } else {
                Style::default()
            };
            lines.push(Line::from(Span::styled(
                format!("{prefix}{}", option.description),
                style,
            )));
        }
        lines.push(Line::from(""));
        lines.push(Line::from(Span::styled(
            "↑↓ navigate   enter select   escape/ctrl+c cancel",
            THEME.muted_text(),
        )));
        lines
    }

    fn menu_question(&self) -> Option<&'static str> {
        match self.mode {
            AppMode::AwaitingConnectMethod { .. } => Some("Select authentication method:"),
            AppMode::AwaitingProvider { .. } => Some("Choose a provider:"),
            _ => None,
        }
    }

    fn menu_options(&self) -> Option<&'static [MenuOption]> {
        match self.mode {
            AppMode::AwaitingConnectMethod { .. } => Some(CONNECT_METHODS),
            AppMode::AwaitingProvider { .. } => Some(PROVIDERS),
            _ => None,
        }
    }

    pub fn should_show_commands(&self) -> bool {
        self.show_commands && self.is_normal()
    }

    /// Recompute `show_commands` and reset the slash-menu selection. Called
    /// by the input handler after every change so the menu hides as soon as
    /// the typed query no longer matches any slash command.
    pub fn recompute_show_commands(&mut self) {
        let now_showing = self.is_normal()
            && self.input.starts_with('/')
            && !filter_slash_commands(self.input.trim_start_matches('/')).is_empty();
        if now_showing {
            // Always start with the first match highlighted after a change.
            self.slash_selected = Some(0);
        } else {
            self.slash_selected = None;
        }
        self.show_commands = now_showing;
    }

    /// Move the selection in the active menu (connect flow or slash) one
    /// step up. No-op when nothing is navigable.
    pub fn select_up(&mut self) {
        match self.mode {
            AppMode::AwaitingConnectMethod { ref mut selected } => {
                let len = CONNECT_METHODS.len();
                *selected = selected.checked_sub(1).unwrap_or(len - 1);
            }
            AppMode::AwaitingProvider { ref mut selected } => {
                let len = PROVIDERS.len();
                *selected = selected.checked_sub(1).unwrap_or(len - 1);
            }
            AppMode::Normal if self.show_commands => self.slash_select_up(),
            _ => {}
        }
    }

    /// Move the selection in the active menu (connect flow or slash) one
    /// step down. No-op when nothing is navigable.
    pub fn select_down(&mut self) {
        match self.mode {
            AppMode::AwaitingConnectMethod { ref mut selected } => {
                let len = CONNECT_METHODS.len();
                *selected = (*selected + 1) % len;
            }
            AppMode::AwaitingProvider { ref mut selected } => {
                let len = PROVIDERS.len();
                *selected = (*selected + 1) % len;
            }
            AppMode::Normal if self.show_commands => self.slash_select_down(),
            _ => {}
        }
    }

    fn slash_select_up(&mut self) {
        let len = filter_slash_commands(self.input.trim_start_matches('/')).len();
        if len == 0 {
            self.slash_selected = None;
            return;
        }
        self.slash_selected = Some(match self.slash_selected {
            Some(0) | None => len - 1,
            Some(index) => index - 1,
        });
    }

    fn slash_select_down(&mut self) {
        let len = filter_slash_commands(self.input.trim_start_matches('/')).len();
        if len == 0 {
            self.slash_selected = None;
            return;
        }
        self.slash_selected = Some(match self.slash_selected {
            Some(index) if index + 1 < len => index + 1,
            _ => 0,
        });
    }

    /// Confirm the current selection. In a connect-flow menu this advances
    /// the state machine; in the slash menu it executes the highlighted
    /// command; otherwise the typed input is submitted.
    pub fn confirm(&mut self) {
        match self.mode {
            AppMode::AwaitingConnectMethod { .. } | AppMode::AwaitingProvider { .. } => {
                self.confirm_menu();
            }
            AppMode::Normal if self.show_commands && self.slash_selected.is_some() => {
                self.confirm_slash_selection();
            }
            AppMode::Connecting => {}
            _ => self.submit(),
        }
    }

    fn confirm_menu(&mut self) {
        let selected = match self.mode {
            AppMode::AwaitingConnectMethod { selected } => selected,
            AppMode::AwaitingProvider { selected } => selected,
            _ => return,
        };
        let value = match self.mode {
            AppMode::AwaitingConnectMethod { .. } => CONNECT_METHODS[selected].value,
            AppMode::AwaitingProvider { .. } => PROVIDERS[selected].value,
            _ => unreachable!(),
        };
        match (self.mode.clone(), value) {
            (AppMode::AwaitingConnectMethod { .. }, "account") => self.enter_provider(),
            (AppMode::AwaitingConnectMethod { .. }, "api-key") => {
                self.begin_api_key_input("openrouter", false);
            }
            (AppMode::AwaitingProvider { .. }, "openrouter") => {
                self.begin_oauth_flow("openrouter");
            }
            _ => {}
        }
    }

    fn confirm_slash_selection(&mut self) {
        let commands = filter_slash_commands(self.input.trim_start_matches('/'));
        let Some(index) = self.slash_selected else {
            return;
        };
        let Some(command) = commands.get(index) else {
            return;
        };
        self.input = format!("/{}", command.name);
        self.slash_selected = None;
        self.show_commands = false;
        self.submit();
    }
}
