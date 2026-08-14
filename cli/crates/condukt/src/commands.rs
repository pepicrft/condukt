//! Canonical metadata and parsing for interactive slash commands.

use fuzzy_matcher::{FuzzyMatcher, skim::SkimMatcherV2};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SlashCommandKind {
    Connect,
    Files,
    Help,
    Quit,
    Read,
}

/// One row in the slash-command menu and one executable command definition.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SlashCommand {
    pub kind: SlashCommandKind,
    pub name: &'static str,
    pub usage: &'static str,
    pub description: &'static str,
}

pub const SLASH_COMMANDS: &[SlashCommand] = &[
    SlashCommand {
        kind: SlashCommandKind::Connect,
        name: "connect",
        usage: "/connect",
        description: "Connect OpenRouter",
    },
    SlashCommand {
        kind: SlashCommandKind::Files,
        name: "files",
        usage: "/files",
        description: "List workspace files",
    },
    SlashCommand {
        kind: SlashCommandKind::Help,
        name: "help",
        usage: "/help",
        description: "Show available commands",
    },
    SlashCommand {
        kind: SlashCommandKind::Quit,
        name: "quit",
        usage: "/quit",
        description: "Exit Condukt",
    },
    SlashCommand {
        kind: SlashCommandKind::Read,
        name: "read",
        usage: "/read <path>",
        description: "Read a workspace file",
    },
];

pub struct ParsedSlashCommand<'a> {
    pub definition: &'static SlashCommand,
    pub argument: &'a str,
}

pub fn parse_slash_command(input: &str) -> Option<ParsedSlashCommand<'_>> {
    let command = input.strip_prefix('/')?;
    let (name, argument) = command
        .split_once(char::is_whitespace)
        .map_or((command, ""), |(name, argument)| (name, argument.trim()));
    let definition = SLASH_COMMANDS.iter().find(|command| command.name == name)?;
    Some(ParsedSlashCommand {
        definition,
        argument,
    })
}

pub fn help_text() -> String {
    let usages = SLASH_COMMANDS
        .iter()
        .map(|command| command.usage)
        .collect::<Vec<_>>()
        .join(", ");
    format!("Commands: {usages}")
}

pub fn filter_slash_commands(query: &str) -> Vec<SlashCommand> {
    if query.is_empty() {
        return SLASH_COMMANDS.to_vec();
    }
    let matcher = SkimMatcherV2::default();
    let mut scored: Vec<(i64, SlashCommand)> = SLASH_COMMANDS
        .iter()
        .copied()
        .filter_map(|command| {
            let candidate = format!("/{} {}", command.name, command.description);
            matcher
                .fuzzy_match(&candidate, query)
                .map(|score| (score, command))
        })
        .collect();
    scored.sort_by_key(|(score, _)| std::cmp::Reverse(*score));
    scored.into_iter().map(|(_, command)| command).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_an_argument_without_losing_spaces_inside_it() {
        let parsed = parse_slash_command("/read folder/my file.rs").expect("known command");
        assert_eq!(parsed.definition.kind, SlashCommandKind::Read);
        assert_eq!(parsed.argument, "folder/my file.rs");
    }

    #[test]
    fn help_is_generated_from_the_command_catalogue() {
        let help = help_text();
        for command in SLASH_COMMANDS {
            assert!(help.contains(command.usage));
        }
    }
}
