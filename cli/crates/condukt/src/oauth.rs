//! OAuth2 PKCE helper with a one-shot loopback HTTP server.
//!
//! Providers (OpenRouter, OpenAI) ship slightly different authorize/token
//! shapes, but the same plumbing applies: generate a PKCE pair, start a
//! loopback server, hand the user a URL to visit, wait for the browser
//! callback, and exchange the authorization code for a credential. This
//! module owns that plumbing so each provider only has to declare the
//! endpoints and how to parse the token response.

use std::{
    io::{Read, Write},
    net::TcpListener,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
        mpsc,
    },
    thread,
    time::{Duration, Instant},
};

use anyhow::{Result, anyhow};
use base64::Engine;
use sha2::{Digest, Sha256};

/// PKCE verifier + S256 challenge. RFC 7636.
pub struct PkcePair {
    pub verifier: String,
    pub challenge: String,
}

const UNRESERVED: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~";

/// Generate a fresh PKCE pair. The verifier is 64 random unreserved
/// characters; the challenge is the base64url-encoded SHA-256 of the
/// verifier bytes.
pub fn generate_pkce() -> Result<PkcePair> {
    let mut bytes = [0u8; 64];
    getrandom::fill(&mut bytes)
        .map_err(|error| anyhow!("Could not generate a secure sign-in verifier: {error}"))?;
    let verifier: String = bytes
        .iter()
        .map(|byte| UNRESERVED[(*byte as usize) % UNRESERVED.len()] as char)
        .collect();

    let mut hasher = Sha256::new();
    hasher.update(verifier.as_bytes());
    let digest = hasher.finalize();
    let challenge = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(digest);

    Ok(PkcePair {
        verifier,
        challenge,
    })
}

/// State a one-shot loopback callback can be in.
#[derive(Debug)]
pub enum CallbackResult {
    Code(String),
}

mod callback_page;

pub use callback_page::{CallbackPage, callback_page};

const CALLBACK_POLL_INTERVAL: Duration = Duration::from_millis(25);
const CALLBACK_READ_TIMEOUT: Duration = Duration::from_millis(500);

/// An owned one-shot loopback server. Dropping it requests cancellation and
/// joins the listener thread, so timed-out sign-in attempts do not leave
/// detached threads behind.
pub struct CallbackServer {
    port: u16,
    receiver: mpsc::Receiver<Result<CallbackResult, String>>,
    cancelled: Arc<AtomicBool>,
    listener: Option<thread::JoinHandle<()>>,
}

impl CallbackServer {
    pub fn port(&self) -> u16 {
        self.port
    }

    pub fn wait(self, cancelled: &AtomicBool) -> Result<CallbackResult> {
        loop {
            if cancelled.load(Ordering::Acquire) {
                return Err(anyhow!("Sign-in cancelled"));
            }
            match self.receiver.recv_timeout(CALLBACK_POLL_INTERVAL) {
                Ok(Ok(result)) => return Ok(result),
                Ok(Err(error)) => return Err(anyhow!(error)),
                Err(mpsc::RecvTimeoutError::Timeout) => {}
                Err(mpsc::RecvTimeoutError::Disconnected) => {
                    return Err(anyhow!("Sign-in callback server stopped unexpectedly"));
                }
            }
        }
    }

    fn stop(&mut self) {
        self.cancelled.store(true, Ordering::Release);
        if let Some(listener) = self.listener.take() {
            let _ = listener.join();
        }
    }
}

impl Drop for CallbackServer {
    fn drop(&mut self) {
        self.stop();
    }
}

/// Bind a loopback server on an ephemeral port and stop it after `timeout`.
pub fn bind_loopback(path: &str, timeout: Duration) -> Result<CallbackServer> {
    let listener = TcpListener::bind("127.0.0.1:0")?;
    listener.set_nonblocking(true)?;
    let port = listener.local_addr()?.port();
    let (tx, rx) = mpsc::channel();
    let expected_path = path.to_string();
    let cancelled = Arc::new(AtomicBool::new(false));
    let listener_cancelled = Arc::clone(&cancelled);

    let handle = thread::spawn(move || {
        let started_at = Instant::now();
        loop {
            if listener_cancelled.load(Ordering::Acquire) {
                return;
            }
            if started_at.elapsed() >= timeout {
                let _ = tx.send(Err("Timed out waiting for the sign-in callback".to_string()));
                return;
            }
            match listener.accept() {
                Ok((mut stream, _)) => {
                    let _ = stream.set_read_timeout(Some(CALLBACK_READ_TIMEOUT));
                    let outcome = handle_callback(&mut stream, &expected_path)
                        .map_err(|error| error.to_string());
                    let _ = tx.send(outcome);
                    return;
                }
                Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                    thread::sleep(CALLBACK_POLL_INTERVAL);
                }
                Err(error) => {
                    let _ = tx.send(Err(format!("Sign-in callback listener failed: {error}")));
                    return;
                }
            }
        }
    });

    Ok(CallbackServer {
        port,
        receiver: rx,
        cancelled,
        listener: Some(handle),
    })
}

fn handle_callback(
    stream: &mut std::net::TcpStream,
    expected_path: &str,
) -> Result<CallbackResult> {
    let mut buffer = vec![0u8; 4096];
    let read = stream.read(&mut buffer)?;
    let request = String::from_utf8_lossy(&buffer[..read]);
    let path =
        request_line_path(&request).ok_or_else(|| anyhow!("Malformed sign-in callback request"))?;
    if path.split('?').next() != Some(expected_path) {
        send_response(stream, 404, &callback_page(CallbackPage::Error))?;
        return Err(anyhow!("Unexpected callback path: {path}"));
    }
    let query = path.split_once('?').map(|(_, query)| query).unwrap_or("");
    if let Some(error) = query_param(query, "error") {
        let description = query_param(query, "error_description").unwrap_or_default();
        send_response(stream, 400, &callback_page(CallbackPage::Error))?;
        return Err(anyhow!("Sign-in failed: {error}: {description}"));
    }
    let code = query_param(query, "code")
        .ok_or_else(|| anyhow!("Sign-in callback did not include a code"))?;
    send_response(stream, 200, &callback_page(CallbackPage::Success))?;
    Ok(CallbackResult::Code(code))
}

/// Pull the request line's path component out of a raw HTTP request.
fn request_line_path(request: &str) -> Option<&str> {
    let line = request.lines().next()?;
    let target = line.split_whitespace().nth(1)?;
    Some(target)
}

fn query_param(query: &str, name: &str) -> Option<String> {
    for pair in query.split('&') {
        let (key, value) = pair.split_once('=')?;
        if key == name {
            return Some(url_decode(value));
        }
    }
    None
}

fn url_decode(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    let mut chars = input.chars().peekable();
    while let Some(ch) = chars.next() {
        if ch == '+' {
            out.push(' ');
        } else if ch == '%' {
            let hex: String = chars.by_ref().take(2).collect();
            if let Ok(byte) = u8::from_str_radix(&hex, 16) {
                out.push(byte as char);
            }
        } else {
            out.push(ch);
        }
    }
    out
}

fn send_response(stream: &mut std::net::TcpStream, status: u16, body: &str) -> Result<()> {
    let reason = match status {
        200 => "OK",
        400 => "Bad Request",
        404 => "Not Found",
        _ => "OK",
    };
    let payload = format!(
        "HTTP/1.1 {status} {reason}\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
        body.len()
    );
    stream.write_all(payload.as_bytes())?;
    stream.flush()?;
    Ok(())
}

#[cfg(test)]
mod tests;
