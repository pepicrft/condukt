//! A status footer that shows the worktree, the associated pull request, and
//! the CI checks for it.
//!
//! The data is collected in a background thread so the TUI frame loop never
//! blocks on `git` or `gh` calls. The thread updates a shared `FooterState`
//! every few seconds; the UI snapshots it at draw time.

use std::{
    path::{Path, PathBuf},
    process::Command,
    sync::{Arc, Mutex, mpsc},
    thread,
    time::{Duration, Instant},
};

use ratatui::{
    style::{Color, Style},
    text::{Line, Span},
};
use unicode_width::{UnicodeWidthChar, UnicodeWidthStr};

const REFRESH_INTERVAL: Duration = Duration::from_secs(5);
const COMMAND_TIMEOUT: Duration = Duration::from_secs(4);
/// All footer text uses this color so the line reads as metadata, not
/// as actionable content. The PR link still gets an OSC 8 hyperlink on
/// top of this dim foreground.
const DIM: Style = Style::new().fg(Color::DarkGray);

/// One chunk of data the footer renders. Kept in a single struct so the
/// background thread can fill all fields in one critical section.
#[derive(Clone, Default)]
struct FooterState {
    branch: Option<String>,
    pr: Option<PrInfo>,
    ci: Option<CiStatus>,
    /// When the last successful refresh happened. `None` until the first
    /// poll completes; the UI uses it to show a stale indicator.
    refreshed_at: Option<Instant>,
}

#[derive(Clone, Debug)]
struct PrInfo {
    number: u64,
}

#[derive(Clone, Copy, Debug)]
struct CiStatus {
    passing: u32,
    failing: u32,
    pending: u32,
}

pub struct Footer {
    working_dir: PathBuf,
    state: Arc<Mutex<FooterState>>,
    refresh: Option<RefreshWorker>,
}

struct RefreshWorker {
    stop: mpsc::Sender<()>,
    handle: Option<thread::JoinHandle<()>>,
}

impl Footer {
    /// Build a footer for the given working directory. The background
    /// refresh thread is started immediately.
    pub fn new(working_dir: PathBuf) -> Self {
        let state = Arc::new(Mutex::new(FooterState::default()));
        let refresh_state = Arc::clone(&state);
        let refresh_dir = working_dir.clone();
        let (stop, stop_receiver) = mpsc::channel();
        let refresh = thread::spawn(move || {
            refresh_loop(refresh_dir, refresh_state, stop_receiver);
        });
        Self {
            working_dir,
            state,
            refresh: Some(RefreshWorker {
                stop,
                handle: Some(refresh),
            }),
        }
    }

    /// Build a footer snapshot without starting background work. Tests and
    /// bare application state use this constructor.
    pub fn inert(working_dir: PathBuf) -> Self {
        Self {
            working_dir,
            state: Arc::new(Mutex::new(FooterState::default())),
            refresh: None,
        }
    }

    /// Render one compact status line. Pull-request data is deliberately
    /// omitted because the host application already owns that presentation.
    pub fn lines(&self, width: u16) -> Vec<Line<'static>> {
        let state = self.state.lock().expect("footer mutex poisoned").clone();
        let mut left = format!(
            "{} ({})",
            shorten_path(&self.working_dir),
            state.branch.as_deref().unwrap_or("detached"),
        );
        if let Some(ci_summary) = state.ci.as_ref().and_then(|ci| format_ci(*ci)) {
            left.push_str(" · ");
            left.push_str(&ci_summary);
        }
        vec![line_with_right_spans(width, &left, model_spans(), DIM)]
    }
}

impl Drop for Footer {
    fn drop(&mut self) {
        let Some(worker) = &mut self.refresh else {
            return;
        };
        let _ = worker.stop.send(());
        if let Some(handle) = worker.handle.take() {
            let _ = handle.join();
        }
    }
}

// -- Rendering helpers --------------------------------------------------------

/// Build a `Line` with `left` text on the left, padding in the middle,
/// and the provided right-hand-side `spans` flush right. The caller is
/// responsible for the styling of the right-hand side so it can include
/// hyperlinks or any other Span-level styling.
fn line_with_right_spans(
    width: u16,
    left: &str,
    right_spans: Vec<Span<'static>>,
    left_style: Style,
) -> Line<'static> {
    let available = width as usize;
    if available == 0 {
        return Line::from(Span::styled(left.to_string(), left_style));
    }
    let right_width: usize = right_spans
        .iter()
        .map(|span| span.content.as_ref().width())
        .sum();
    let left_width = left.width();
    if left_width + right_width + 1 >= available {
        return Line::from(Span::styled(truncate(left, available), left_style));
    }
    let padding = available - left_width - right_width;
    let mut spans = vec![Span::styled(left.to_string(), left_style)];
    spans.push(Span::raw(" ".repeat(padding)));
    spans.extend(right_spans);
    Line::from(spans)
}

fn truncate(input: &str, max: usize) -> String {
    if input.width() <= max {
        return input.to_string();
    }
    if max == 0 {
        return String::new();
    }
    if max == 1 {
        return "\u{2026}".to_string();
    }
    let budget = max - 1;
    let mut width = 0;
    let mut end = 0;
    for (index, character) in input.char_indices() {
        let character_width = UnicodeWidthChar::width(character).unwrap_or(0);
        if width + character_width > budget {
            break;
        }
        width += character_width;
        end = index + character.len_utf8();
    }
    let mut out = input[..end].to_string();
    out.push('\u{2026}');
    out
}

fn shorten_path(path: &Path) -> String {
    let home = std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_default();
    let stripped = home
        .as_path()
        .ancestors()
        .find(|ancestor| path.strip_prefix(ancestor).is_ok())
        .and_then(|ancestor| path.strip_prefix(ancestor).ok())
        .map(|p| p.to_path_buf())
        .unwrap_or_else(|| path.to_path_buf());
    let mut display = if home.as_os_str().is_empty() {
        stripped.display().to_string()
    } else {
        format!("~{}", stripped.display())
    };
    // Keep at most the last two components so a long path does not eat
    // the footer.
    let components: Vec<&str> = display.split('/').filter(|c| !c.is_empty()).collect();
    if components.len() > 3 {
        display = format!("\u{2026}/{}", components[components.len() - 2..].join("/"));
    }
    display
}

/// Right-hand side of the second footer row. Always present so the
/// model line stays anchored even when there are no CI checks.
fn model_spans() -> Vec<Span<'static>> {
    vec![Span::styled(
        "(openrouter) model \u{b7} effort".to_string(),
        DIM,
    )]
}

/// Render CI counts as a short left-aligned summary. Returns `None`
/// when there are no checks at all, so the caller can leave the line
/// empty instead of printing a placeholder.
fn format_ci(ci: CiStatus) -> Option<String> {
    let mut parts = Vec::new();
    if ci.passing > 0 {
        parts.push(format!("\u{2713} {pass} passing", pass = ci.passing));
    }
    if ci.failing > 0 {
        parts.push(format!("\u{2717} {fail} failing", fail = ci.failing));
    }
    if ci.pending > 0 {
        parts.push(format!("\u{22ef} {pending} pending", pending = ci.pending));
    }
    if parts.is_empty() {
        None
    } else {
        Some(format!("CI: {}", parts.join(", ")))
    }
}

// -- Background refresh -------------------------------------------------------

fn refresh_loop(working_dir: PathBuf, state: Arc<Mutex<FooterState>>, stop: mpsc::Receiver<()>) {
    loop {
        // Errors are intentionally swallowed: a failing `gh` invocation
        // should not write to stderr while the TUI is drawing, and the
        // footer should simply stop showing the data that failed to
        // refresh until the next successful poll.
        refresh_once(&working_dir, &state);
        match stop.recv_timeout(REFRESH_INTERVAL) {
            Ok(()) | Err(mpsc::RecvTimeoutError::Disconnected) => return,
            Err(mpsc::RecvTimeoutError::Timeout) => {}
        }
    }
}

fn refresh_once(working_dir: &Path, state: &Arc<Mutex<FooterState>>) {
    let branch = git_branch(working_dir);
    // PR info and CI status are queried independently: a missing
    // `gh pr checks` result (e.g. before CI has run) should not blank
    // out the PR we just found.
    let pr = branch
        .as_deref()
        .and_then(|branch| gh_pr_view(working_dir, branch).ok().flatten());
    let ci = pr
        .as_ref()
        .and_then(|info| gh_pr_checks(working_dir, info.number).ok().flatten());
    let mut guard = state.lock().expect("footer mutex poisoned");
    guard.branch = branch;
    guard.pr = pr;
    guard.ci = ci;
    guard.refreshed_at = Some(Instant::now());
}

fn git_branch(working_dir: &Path) -> Option<String> {
    run_command("git", &["rev-parse", "--abbrev-ref", "HEAD"], working_dir)
        .ok()
        .filter(|output| !output.is_empty())
}

fn gh_pr_view(working_dir: &Path, branch: &str) -> anyhow::Result<Option<PrInfo>> {
    let Some(output) = run_command(
        "gh",
        &["pr", "view", branch, "--json", "number"],
        working_dir,
    )
    .ok() else {
        return Ok(None);
    };
    if output.is_empty() {
        return Ok(None);
    }
    let parsed: serde_json::Value = serde_json::from_str(&output)?;
    let number = parsed
        .get("number")
        .and_then(serde_json::Value::as_u64)
        .ok_or_else(|| anyhow::anyhow!("missing PR number"))?;
    Ok(Some(PrInfo { number }))
}

fn gh_pr_checks(working_dir: &Path, number: u64) -> anyhow::Result<Option<CiStatus>> {
    let output = run_command(
        "gh",
        &[
            "pr",
            "checks",
            &number.to_string(),
            "--json",
            "name,conclusion",
        ],
        working_dir,
    )?;
    if output.is_empty() {
        return Ok(None);
    }
    let parsed: Vec<serde_json::Value> = serde_json::from_str(&output)?;
    let mut passing = 0u32;
    let mut failing = 0u32;
    let mut pending = 0u32;
    for check in parsed {
        match check
            .get("conclusion")
            .and_then(serde_json::Value::as_str)
            .unwrap_or("")
        {
            "SUCCESS" => passing += 1,
            "FAILURE" | "CANCELLED" | "TIMED_OUT" | "ACTION_REQUIRED" => failing += 1,
            _ => pending += 1,
        }
    }
    Ok(Some(CiStatus {
        passing,
        failing,
        pending,
    }))
}

fn run_command(program: &str, args: &[&str], working_dir: &Path) -> anyhow::Result<String> {
    let mut child = Command::new(program)
        .args(args)
        .current_dir(working_dir)
        .env_remove("GH_TOKEN")
        .env("NO_COLOR", "1")
        .env("GH_NO_UPDATE_NOTIFIER", "1")
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()?;
    let start = Instant::now();
    loop {
        if start.elapsed() > COMMAND_TIMEOUT {
            let _ = child.kill();
            anyhow::bail!("{program} {} timed out", args.join(" "));
        }
        match child.try_wait()? {
            Some(status) => {
                if !status.success() {
                    anyhow::bail!("{program} {} exited with {status}", args.join(" "));
                }
                let mut output = String::new();
                if let Some(mut stdout) = child.stdout.take() {
                    use std::io::Read;
                    stdout.read_to_string(&mut output)?;
                }
                return Ok(output.trim().to_string());
            }
            None => thread::sleep(Duration::from_millis(50)),
        }
    }
}

#[cfg(test)]
mod tests;
