//! Non-interactive execution for scripts, continuous integration, and pipes.

use std::{
    io::{self, IsTerminal, Read},
    path::PathBuf,
};

use crate::agent_prompt::CODING_AGENT_PROMPT;
use crate::cli::ColorChoice;
use crate::syntax::highlight_markdown;
use anyhow::{Context, Result, anyhow};
use condukt_openrouter::OpenRouterInferenceProvider;
use condukt_session::{AgentEvent, Session};
use serde_json::json;

use crate::local_tools::LocalToolSet;

/// Execute a single task and write only the final response to standard output.
pub fn run(
    prompt: Option<String>,
    api_key: Option<String>,
    cwd: Option<PathBuf>,
    verbose: bool,
    json_output: bool,
    color: ColorChoice,
) -> Result<()> {
    let prompt = prompt.map(Ok).unwrap_or_else(read_prompt)?;
    anyhow::ensure!(!prompt.trim().is_empty(), "a prompt is required");

    let root = cwd.unwrap_or(std::env::current_dir()?);
    anyhow::ensure!(
        root.is_dir(),
        "workspace does not exist: {}",
        root.display()
    );
    let api_key = api_key.or_else(|| std::env::var("CONDUKT_OPENROUTER_API_KEY").ok());
    let provider = match api_key {
        Some(key) => OpenRouterInferenceProvider::new(key),
        None => OpenRouterInferenceProvider::from_saved_key()?
            .ok_or_else(|| anyhow!("not connected; run `condukt connect openrouter --api-key <key>` or set CONDUKT_OPENROUTER_API_KEY"))?,
    };
    let tools = LocalToolSet::new(root);
    let definitions = tools.definitions();
    let mut session = Session::with_system_prompt(provider, CODING_AGENT_PROMPT);
    let response = session
        .submit_with_tools(prompt, definitions, &tools, &mut |event| {
            if verbose {
                print_event(event);
            }
        })
        .map_err(|error| anyhow!(error.to_string()))?;

    if json_output {
        println!(
            "{}",
            serde_json::to_string(&json!({ "response": response.content }))?
        );
    } else {
        let output = if matches!(color, ColorChoice::Always)
            || (matches!(color, ColorChoice::Auto) && io::stdout().is_terminal())
        {
            highlight_markdown(&response.content)
        } else {
            response.content
        };
        println!("{output}");
    }
    Ok(())
}

fn read_prompt() -> Result<String> {
    anyhow::ensure!(
        !io::stdin().is_terminal(),
        "a prompt is required; use `condukt exec <prompt>`, `condukt -p <prompt>`, or pipe it on standard input"
    );
    let mut prompt = String::new();
    io::stdin()
        .read_to_string(&mut prompt)
        .context("could not read prompt from standard input")?;
    Ok(prompt)
}

fn print_event(event: AgentEvent) {
    match event {
        AgentEvent::Text(text) => eprintln!("assistant: {text}"),
        AgentEvent::ToolCall { name, arguments } => eprintln!("tool call: {name} {arguments}"),
        AgentEvent::ToolResult {
            name,
            output,
            error,
        } => match error {
            Some(error) => eprintln!("tool error: {name}: {error}"),
            None => eprintln!("tool result: {name}: {output}"),
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tool_chain_exposes_read_and_bash() {
        let tools = LocalToolSet::new(std::env::temp_dir());
        let definitions = tools.definitions();
        let names: Vec<_> = definitions.iter().map(|tool| tool.name.as_str()).collect();
        assert_eq!(names, ["read", "bash"]);
    }
}
