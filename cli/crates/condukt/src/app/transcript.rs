use super::*;

impl App {
    pub fn push_prompt_echo(&mut self, prompt: &str) {
        self.begin_activity_group();
        self.document
            .push(message_header(&self.user_name, THEME.user_marker()));
        self.document
            .push(message_body(prompt, THEME.user_marker()));
    }

    pub fn push_info(&mut self, message: impl Into<String>) {
        self.document.push(Line::from(message.into()));
    }

    /// Add a user-visible error as a titled red message block. Keeping errors
    /// in their own activity group makes them readable beside user and model
    /// messages, rather than running into the preceding transcript entry.
    pub fn push_error(&mut self, message: impl Into<String>) {
        self.begin_activity_group();
        self.document
            .push(message_header("Error", THEME.error_marker()));
        self.document
            .push(message_body(&message.into(), THEME.error_marker()));
    }

    /// Separate a new model or tool activity group from the preceding
    /// conversation entry. Tool results stay attached to their invocation.
    fn begin_activity_group(&mut self) {
        if self
            .document
            .last()
            .is_some_and(|line| !line.to_string().trim().is_empty())
        {
            self.document.push(Line::from(""));
        }
    }

    pub(super) fn handle_agent_event(&mut self, event: AgentEvent) {
        match event {
            AgentEvent::Text(text) => {
                if text.trim().is_empty() {
                    return;
                }
                self.begin_activity_group();
                self.document
                    .push(message_header(&self.model_name, THEME.activity_marker()));
                for line in text.lines() {
                    self.document
                        .push(message_body(line, THEME.activity_marker()));
                }
            }
            AgentEvent::ToolCall { name, arguments } => {
                self.begin_activity_group();
                self.document.push(tool_call_line(&name, &arguments));
            }
            AgentEvent::ToolResult {
                name,
                output,
                error,
            } => {
                self.document.push(tool_result_line(&name, output, error));
            }
        }
    }
}

fn message_header(label: &str, marker: Style) -> Line<'static> {
    Line::from(vec![
        Span::styled("▌ ", marker),
        Span::styled(label.to_string(), marker.add_modifier(Modifier::BOLD)),
    ])
}

fn message_body(content: &str, marker: Style) -> Line<'static> {
    Line::from(vec![
        Span::styled("▌ ", marker),
        Span::styled(content.to_string(), THEME.text()),
    ])
}

/// tool name bolded and the arguments dimmed, gPi-style.
pub(super) fn tool_call_line(name: &str, arguments: &str) -> Line<'static> {
    Line::from(vec![
        Span::styled("▌ ", THEME.activity_marker()),
        Span::styled(format!("tool {name}"), THEME.selected()),
        Span::styled(
            format!(" {}", summarize_args(arguments)),
            THEME.muted_italic(),
        ),
    ])
}

/// Render a tool result line. The body is the first line of the output;
/// errors are shown in red.
pub(super) fn tool_result_line(name: &str, output: String, error: Option<String>) -> Line<'static> {
    let has_error = error.is_some();
    let mut spans = vec![
        Span::styled(
            if has_error { "▌ " } else { "┆ " },
            if has_error {
                THEME.error_marker()
            } else {
                THEME.muted_text()
            },
        ),
        Span::styled(name.to_string(), THEME.muted_text()),
    ];
    match error {
        Some(message) => {
            spans.push(Span::raw(" "));
            spans.push(Span::styled(
                truncate_for_display(&message, 240),
                THEME.error_text(),
            ));
        }
        None => {
            let first_line = output.lines().next().unwrap_or("");
            spans.push(Span::raw(" "));
            spans.push(Span::styled(first_line.to_string(), THEME.muted_text()));
        }
    }
    Line::from(spans)
}

fn summarize_args(arguments: &str) -> String {
    truncate_with_ellipsis(arguments.trim(), 200)
}

fn truncate_for_display(input: &str, max: usize) -> String {
    truncate_with_ellipsis(&input.replace('\n', " "), max)
}

fn truncate_with_ellipsis(input: &str, max_characters: usize) -> String {
    let mut characters = input.chars();
    let prefix: String = characters.by_ref().take(max_characters).collect();
    if characters.next().is_some() {
        format!("{prefix}\u{2026}")
    } else {
        prefix
    }
}
