//! OAuth2 PKCE login for OpenRouter.
//!
//! The flow mirrors what `pi-mono` does: generate a PKCE pair, bind a
//! loopback callback server, hand the user an authorize URL, and exchange
//! the captured authorization code for a permanent OpenRouter API key at
//! `/api/v1/auth/keys`. OpenRouter does not issue a client secret for the
//! PKCE flow, so the only secrets involved are the verifier (kept in
//! memory) and the resulting key (saved via `save_key`).

use std::{sync::atomic::AtomicBool, time::Duration};

use anyhow::{Result, anyhow};
use condukt_openrouter::shared_agent;

use crate::oauth::{CallbackResult, CallbackServer, PkcePair, bind_loopback, generate_pkce};

const AUTHORIZE_URL: &str = "https://openrouter.ai/auth";
const TOKEN_URL: &str = "https://openrouter.ai/api/v1/auth/keys";
const CALLBACK_PATH: &str = "/oauth/callback/condukt";
const LOGIN_TIMEOUT: Duration = Duration::from_secs(5 * 60);

/// A browser sign-in attempt that has opened its callback listener but has
/// not yet waited for the browser or exchanged the authorization code.
pub struct PendingLogin {
    callback: CallbackServer,
    pkce: PkcePair,
    authorize_url: String,
}

impl PendingLogin {
    pub fn authorize_url(&self) -> &str {
        &self.authorize_url
    }

    pub fn complete(self, cancelled: &AtomicBool) -> Result<String> {
        let outcome = self.callback.wait(cancelled)?;
        let CallbackResult::Code(code) = outcome;
        if cancelled.load(std::sync::atomic::Ordering::Acquire) {
            return Err(anyhow!("Sign-in cancelled"));
        }
        exchange_code(&code, &self.pkce.verifier)
    }
}

/// Start browser sign-in without blocking the caller.
pub fn start_login() -> Result<PendingLogin> {
    let pkce = generate_pkce()?;
    let callback = bind_loopback(CALLBACK_PATH, LOGIN_TIMEOUT)?;
    let callback_url = format!("http://127.0.0.1:{}{CALLBACK_PATH}", callback.port());

    let authorize_url = format!(
        "{AUTHORIZE_URL}?callback_url={callback}&code_challenge={challenge}&code_challenge_method=S256",
        callback = url_encode(&callback_url),
        challenge = url_encode(&pkce.challenge),
    );

    Ok(PendingLogin {
        callback,
        pkce,
        authorize_url,
    })
}

/// Run the complete browser sign-in flow for non-interactive hosts.
pub fn login<F>(open_browser: F, cancelled: &AtomicBool) -> Result<String>
where
    F: FnOnce(&str),
{
    let login = start_login()?;
    open_browser(login.authorize_url());
    login.complete(cancelled)
}

fn exchange_code(code: &str, verifier: &str) -> Result<String> {
    let body = serde_json::json!({
        "code": code,
        "code_verifier": verifier,
        "code_challenge_method": "S256",
    });
    let mut response = shared_agent()
        .post(TOKEN_URL)
        .header("accept", "application/json")
        .header("content-type", "application/json")
        .send_json(body)
        .map_err(|error| anyhow!("OpenRouter key exchange request failed: {error}"))?;
    let status = response.status();
    let body: serde_json::Value = response
        .body_mut()
        .read_json()
        .map_err(|error| anyhow!("OpenRouter key exchange returned invalid JSON: {error}"))?;
    if !(200..300).contains(&status.as_u16()) {
        let detail = body
            .get("error")
            .or_else(|| body.get("message"))
            .and_then(|value| value.as_str())
            .unwrap_or("unknown error");
        return Err(anyhow!(
            "OpenRouter OAuth key exchange failed (HTTP {status}): {detail}"
        ));
    }
    let key = body
        .get("key")
        .and_then(|value| value.as_str())
        .ok_or_else(|| anyhow!("OpenRouter OAuth response did not include a key"))?;
    Ok(key.to_string())
}

fn url_encode(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for byte in input.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(byte as char);
            }
            _ => {
                out.push('%');
                out.push_str(&format!("{byte:02X}"));
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn url_encode_passes_through_unreserved() {
        assert_eq!(
            url_encode("http://127.0.0.1:12345/oauth/callback/condukt"),
            "http%3A%2F%2F127.0.0.1%3A12345%2Foauth%2Fcallback%2Fcondukt"
        );
        assert_eq!(url_encode("abc-DEF_123.~"), "abc-DEF_123.~");
    }

    #[test]
    fn starting_login_returns_without_waiting_for_the_callback() {
        let started_at = std::time::Instant::now();
        let login = start_login().expect("login starts");
        assert!(login.authorize_url().starts_with(AUTHORIZE_URL));
        assert!(started_at.elapsed() < Duration::from_secs(1));
    }
}
