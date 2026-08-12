use std::{
    io::Read,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant},
};

use condukt_inference::ToolDefinition;
use serde_json::{Value, json};

/// Outcome of running a tool. `Ok` carries the textual output the model
/// sees; `Err` carries an error message that the model is told about.
pub type ToolResult = Result<String, String>;

/// A tool the model can call. The host owns a `Vec<Box<dyn Tool>>` and
/// hands it to the session, which dispatches incoming `ToolCall`s by name.
pub trait Tool: Send + Sync {
    fn name(&self) -> &'static str;
    fn description(&self) -> &'static str;
    /// JSON Schema describing the function's parameters.
    fn parameters(&self) -> Value;
    fn execute(&self, arguments: &Value) -> ToolResult;

    /// Convenience helper that returns the OpenAI-compatible tool
    /// definition the provider expects.
    fn definition(&self) -> ToolDefinition {
        ToolDefinition {
            name: self.name().to_string(),
            description: self.description().to_string(),
            parameters: self.parameters(),
        }
    }
}

pub fn workspace_files(root: &Path) -> std::io::Result<Vec<PathBuf>> {
    let mut files = Vec::new();
    for entry in root.read_dir()? {
        let entry = entry?;
        if entry.file_type()?.is_file() {
            files.push(entry.path());
        }
    }
    files.sort();
    Ok(files)
}

/// `read(path)` — return the contents of a file as text. The path is
/// resolved relative to `root` when it is not absolute.
pub struct ReadTool {
    pub root: PathBuf,
}

impl Tool for ReadTool {
    fn name(&self) -> &'static str {
        "read"
    }

    fn description(&self) -> &'static str {
        "Read the contents of a file at the given path. Paths are resolved relative to the workspace root unless absolute."
    }

    fn parameters(&self) -> Value {
        json!({
            "type": "object",
            "properties": {
                "path": {
                    "type": "string",
                    "description": "Path to the file to read, relative to the workspace root or absolute."
                }
            },
            "required": ["path"]
        })
    }

    fn execute(&self, arguments: &Value) -> ToolResult {
        let raw = arguments
            .get("path")
            .and_then(Value::as_str)
            .ok_or_else(|| "missing 'path' argument".to_string())?;
        let path = resolve(&self.root, raw);
        let mut file = std::fs::File::open(&path)
            .map_err(|error| format!("could not open {}: {error}", path.display()))?;
        let mut contents = String::new();
        file.read_to_string(&mut contents)
            .map_err(|error| format!("could not read {}: {error}", path.display()))?;
        truncate_output(&mut contents, 50_000);
        Ok(contents)
    }
}

/// `bash(command)` — run a shell command and return its combined
/// `stdout` + `stderr`. The command runs in `root` with a hard timeout.
pub struct BashTool {
    pub root: PathBuf,
    pub timeout: Duration,
}

impl Default for BashTool {
    fn default() -> Self {
        Self {
            root: PathBuf::from("."),
            timeout: Duration::from_secs(30),
        }
    }
}

impl Tool for BashTool {
    fn name(&self) -> &'static str {
        "bash"
    }

    fn description(&self) -> &'static str {
        "Run a shell command in the workspace root and return its combined stdout and stderr. The command has a hard timeout."
    }

    fn parameters(&self) -> Value {
        json!({
            "type": "object",
            "properties": {
                "command": {
                    "type": "string",
                    "description": "Shell command to execute. Runs with sh -c."
                }
            },
            "required": ["command"]
        })
    }

    fn execute(&self, arguments: &Value) -> ToolResult {
        let command = arguments
            .get("command")
            .and_then(Value::as_str)
            .ok_or_else(|| "missing 'command' argument".to_string())?;
        let output = run_command(command, &self.root, self.timeout)?;
        let mut combined = String::new();
        if !output.stdout.is_empty() {
            combined.push_str(&String::from_utf8_lossy(&output.stdout));
        }
        if !output.stderr.is_empty() {
            if !combined.is_empty() && !combined.ends_with('\n') {
                combined.push('\n');
            }
            combined.push_str(&String::from_utf8_lossy(&output.stderr));
        }
        truncate_output(&mut combined, 50_000);
        if !output.status.success() {
            return Err(format!(
                "command exited with status {}: {combined}",
                output.status
            ));
        }
        Ok(combined)
    }
}

fn run_command(
    command: &str,
    root: &Path,
    timeout: Duration,
) -> Result<std::process::Output, String> {
    let mut process = Command::new("sh");
    process
        .arg("-c")
        .arg(command)
        .current_dir(root)
        .env_remove("GH_TOKEN")
        .env("NO_COLOR", "1")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());

    // Give the shell its own process group so a timeout stops descendants as
    // well as the shell itself. Without this, a child can keep the captured
    // output pipes open after the shell has been killed.
    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        process.process_group(0);
    }

    let mut child = process
        .spawn()
        .map_err(|error| format!("could not spawn shell: {error}"))?;
    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| "could not capture shell standard output".to_string())?;
    let stderr = child
        .stderr
        .take()
        .ok_or_else(|| "could not capture shell standard error".to_string())?;
    let stdout_reader = thread::spawn(move || read_pipe(stdout));
    let stderr_reader = thread::spawn(move || read_pipe(stderr));

    let started_at = Instant::now();
    let status = loop {
        match child
            .try_wait()
            .map_err(|error| format!("could not wait for shell: {error}"))?
        {
            Some(status) => break status,
            None if started_at.elapsed() >= timeout => {
                terminate_process(&mut child);
                let _ = child.wait();
                let _ = stdout_reader.join();
                let _ = stderr_reader.join();
                return Err(format!(
                    "command timed out after {:.1} seconds",
                    timeout.as_secs_f64()
                ));
            }
            None => thread::sleep(Duration::from_millis(10)),
        }
    };

    let stdout = join_pipe(stdout_reader, "standard output")?;
    let stderr = join_pipe(stderr_reader, "standard error")?;
    Ok(std::process::Output {
        status,
        stdout,
        stderr,
    })
}

fn read_pipe(mut pipe: impl Read) -> std::io::Result<Vec<u8>> {
    let mut bytes = Vec::new();
    pipe.read_to_end(&mut bytes)?;
    Ok(bytes)
}

fn join_pipe(
    reader: thread::JoinHandle<std::io::Result<Vec<u8>>>,
    label: &str,
) -> Result<Vec<u8>, String> {
    reader
        .join()
        .map_err(|_| format!("shell {label} reader panicked"))?
        .map_err(|error| format!("could not read shell {label}: {error}"))
}

#[cfg(unix)]
fn terminate_process(child: &mut std::process::Child) {
    let process_group = -(child.id() as libc::pid_t);
    // SAFETY: the child was started as the leader of a new process group, so
    // the negative identifier targets only that group. Failure is harmless
    // here because `Child::kill` below still attempts to stop the direct child.
    unsafe {
        libc::kill(process_group, libc::SIGKILL);
    }
    let _ = child.kill();
}

#[cfg(not(unix))]
fn terminate_process(child: &mut std::process::Child) {
    let _ = child.kill();
}

fn truncate_output(output: &mut String, max_bytes: usize) {
    if output.len() <= max_bytes {
        return;
    }
    let mut boundary = max_bytes;
    while !output.is_char_boundary(boundary) {
        boundary -= 1;
    }
    output.truncate(boundary);
    output.push_str("\n... (truncated)");
}

fn resolve(root: &Path, raw: &str) -> PathBuf {
    let candidate = PathBuf::from(raw);
    if candidate.is_absolute() {
        candidate
    } else {
        root.join(candidate)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    fn temp_root() -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "condukt-tools-test-{}",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_nanos())
                .unwrap_or(0)
        ));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn read_tool_returns_file_contents() {
        let root = temp_root();
        let path = root.join("hello.txt");
        let mut file = std::fs::File::create(&path).unwrap();
        writeln!(file, "hello, world").unwrap();
        let tool = ReadTool { root: root.clone() };
        let output = tool
            .execute(&json!({"path": "hello.txt"}))
            .expect("read succeeds");
        assert!(output.contains("hello, world"));
    }

    #[test]
    fn read_tool_truncates_large_files() {
        let root = temp_root();
        let path = root.join("big.txt");
        std::fs::write(&path, "x".repeat(60_000)).unwrap();
        let tool = ReadTool { root };
        let output = tool
            .execute(&json!({"path": "big.txt"}))
            .expect("read succeeds");
        assert!(output.contains("(truncated)"));
    }

    #[test]
    fn read_tool_truncates_unicode_at_a_character_boundary() {
        let root = temp_root();
        let path = root.join("unicode.txt");
        std::fs::write(&path, format!("{}é", "x".repeat(49_999))).unwrap();
        let tool = ReadTool { root };
        let output = tool
            .execute(&json!({"path": "unicode.txt"}))
            .expect("read succeeds");
        assert!(output.ends_with("... (truncated)"));
    }

    #[test]
    fn read_tool_rejects_missing_path() {
        let tool = ReadTool { root: temp_root() };
        let result = tool.execute(&json!({}));
        assert!(result.is_err());
    }

    #[test]
    fn bash_tool_runs_in_root_and_returns_output() {
        let root = temp_root();
        let tool = BashTool {
            root: root.clone(),
            ..BashTool::default()
        };
        let output = tool
            .execute(&json!({"command": "echo hi && pwd"}))
            .expect("bash succeeds");
        assert!(output.contains("hi"));
        // The pwd output should mention the temp root.
        assert!(output.contains(&root.display().to_string()));
    }

    #[test]
    fn bash_tool_surfaces_nonzero_exit_as_error() {
        let tool = BashTool {
            root: temp_root(),
            ..BashTool::default()
        };
        let result = tool.execute(&json!({"command": "exit 7"}));
        assert!(result.is_err());
    }

    #[test]
    fn bash_tool_enforces_its_timeout() {
        let tool = BashTool {
            root: temp_root(),
            timeout: Duration::from_millis(50),
        };
        let started_at = Instant::now();
        let error = tool
            .execute(&json!({"command": "sleep 5"}))
            .expect_err("command should time out");
        assert!(error.contains("timed out"), "got: {error}");
        assert!(started_at.elapsed() < Duration::from_secs(1));
    }

    #[test]
    fn output_truncation_preserves_unicode_boundaries() {
        let mut output = format!("{}é", "x".repeat(49_999));
        truncate_output(&mut output, 50_000);
        assert!(output.ends_with("... (truncated)"));
        assert!(output.is_char_boundary(output.len()));
    }

    #[test]
    fn read_tool_resolves_absolute_paths() {
        let root = temp_root();
        let path = root.join("abs.txt");
        std::fs::write(&path, "absolute content").unwrap();
        let tool = ReadTool { root };
        let output = tool
            .execute(&json!({"path": path.to_str().unwrap()}))
            .expect("read succeeds");
        assert!(output.contains("absolute content"));
    }
}
