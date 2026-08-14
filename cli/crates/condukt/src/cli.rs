use anyhow::Result;
use clap::{Parser, Subcommand, ValueEnum};

use condukt_openrouter::import_pi_openrouter_credential;
use condukt_tools::workspace_files;

use crate::browser::{BrowserOpener, SystemBrowser};
use crate::local_tools::LocalToolSet;

#[derive(Parser)]
#[command(name = "condukt", about = "A coding agent")]
pub struct Cli {
    /// Submit a prompt without starting the terminal interface.
    #[arg(short = 'p', long, global = true)]
    pub prompt: Option<String>,
    #[command(subcommand)]
    pub command: Option<Command>,
}

#[derive(Subcommand)]
pub enum Command {
    /// Copy the OpenRouter credential from Pi without printing it.
    ImportPiCredentials,
    /// Run one coding task without an interactive terminal interface.
    Exec {
        /// Task for Condukt to complete. When omitted, Condukt reads the task from standard input.
        #[arg(value_name = "PROMPT")]
        prompt: Option<String>,
        /// OpenRouter credential. Prefer CONDUKT_OPENROUTER_API_KEY for scripts.
        #[arg(long)]
        api_key: Option<String>,
        /// Directory in which tools run. Defaults to the current directory.
        #[arg(long, value_name = "PATH")]
        cwd: Option<std::path::PathBuf>,
        /// Include tool activity on standard error.
        #[arg(short, long)]
        verbose: bool,
        /// Print the final response as machine-readable data.
        #[arg(long)]
        json: bool,
        /// Control terminal color in the final response.
        #[arg(long, value_enum, default_value_t = ColorChoice::Auto)]
        color: ColorChoice,
    },
    /// Run as a headless Agent Client Protocol server over standard input/output.
    Acp,
    Connect {
        provider: String,
        #[arg(long)]
        api_key: Option<String>,
    },
    /// List files in the workspace root, matching the interactive `/files` command.
    Files {
        #[arg(long, value_name = "PATH")]
        cwd: Option<std::path::PathBuf>,
    },
    /// Read a workspace file, matching the interactive `/read` command.
    Read {
        path: std::path::PathBuf,
        #[arg(long, value_name = "PATH")]
        cwd: Option<std::path::PathBuf>,
    },
}

pub fn run(cli: Cli) -> Result<()> {
    match cli.command {
        Some(Command::Acp) => {
            tokio::runtime::Runtime::new()?.block_on(crate::acp::run())?;
            Ok(())
        }
        Some(Command::ImportPiCredentials) => {
            if import_pi_openrouter_credential()? {
                println!("Imported OpenRouter credential from Pi.");
            } else {
                println!("Condukt already has an OpenRouter credential.");
            }
            Ok(())
        }
        Some(Command::Exec {
            prompt,
            api_key,
            cwd,
            verbose,
            json,
            color,
        }) => crate::headless::run(prompt.or(cli.prompt), api_key, cwd, verbose, json, color),
        Some(Command::Connect { provider, api_key }) => {
            anyhow::ensure!(
                provider.eq_ignore_ascii_case("openrouter"),
                "only OpenRouter is supported currently"
            );
            let cancelled = std::sync::atomic::AtomicBool::new(false);
            let provider = match api_key {
                Some(key) => crate::connection::connect_with_key(key, &cancelled),
                None => {
                    let key =
                        crate::openrouter_oauth::login(|url| SystemBrowser.open(url), &cancelled)
                            .map_err(anyhow::Error::msg)?;
                    crate::connection::connect_with_key(key, &cancelled)
                }
            }
            .map_err(anyhow::Error::msg)?;
            let _ = provider;
            println!("OpenRouter is connected.");
            Ok(())
        }
        Some(Command::Files { cwd }) => {
            let root = cwd.unwrap_or(std::env::current_dir()?);
            for file in workspace_files(&root)? {
                println!("{}", file.display());
            }
            Ok(())
        }
        Some(Command::Read { path, cwd }) => {
            let root = cwd.unwrap_or(std::env::current_dir()?);
            let tools = LocalToolSet::new(root);
            let arguments = serde_json::json!({ "path": path }).to_string();
            let contents = tools
                .execute("read", &arguments)
                .map_err(anyhow::Error::msg)?;
            print!("{contents}");
            Ok(())
        }
        None if cli.prompt.is_some() => {
            crate::headless::run(cli.prompt, None, None, false, false, ColorChoice::Auto)
        }
        None => crate::ui::run(),
    }
}

#[derive(Clone, Copy, Debug, Default, ValueEnum)]
pub enum ColorChoice {
    #[default]
    Auto,
    Always,
    Never,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exec_accepts_a_positional_prompt() {
        let cli = Cli::try_parse_from(["condukt", "exec", "inspect the workspace"]).unwrap();
        let Some(Command::Exec { prompt, .. }) = cli.command else {
            panic!("expected exec command");
        };
        assert_eq!(prompt.as_deref(), Some("inspect the workspace"));
    }

    #[test]
    fn short_prompt_option_starts_headless_mode() {
        let cli = Cli::try_parse_from(["condukt", "-p", "inspect the workspace"]).unwrap();
        assert_eq!(cli.prompt.as_deref(), Some("inspect the workspace"));
        assert!(cli.command.is_none());
    }

    #[test]
    fn connect_can_start_browser_sign_in_without_a_key() {
        let cli = Cli::try_parse_from(["condukt", "connect", "openrouter"]).unwrap();
        let Some(Command::Connect { api_key, .. }) = cli.command else {
            panic!("expected connect command");
        };
        assert!(api_key.is_none());
    }

    #[test]
    fn files_and_read_match_interactive_workspace_commands() {
        let files = Cli::try_parse_from(["condukt", "files"]).unwrap();
        assert!(matches!(files.command, Some(Command::Files { .. })));

        let read = Cli::try_parse_from(["condukt", "read", "README.md"]).unwrap();
        assert!(matches!(read.command, Some(Command::Read { .. })));
    }
}
