//! Host-independent OpenRouter connection workflows.

use std::sync::atomic::{AtomicBool, Ordering};

use condukt_openrouter::{OpenRouterInferenceProvider, save_key};

use crate::openrouter_oauth::PendingLogin;

pub fn connect_with_key(
    key: String,
    cancelled: &AtomicBool,
) -> Result<OpenRouterInferenceProvider, String> {
    ensure_not_cancelled(cancelled)?;
    let provider = OpenRouterInferenceProvider::new(&key);
    provider.validate()?;
    ensure_not_cancelled(cancelled)?;
    save_key(&key).map_err(|error| format!("Failed to save the OpenRouter key: {error}"))?;
    Ok(provider)
}

pub fn complete_browser_login(
    login: PendingLogin,
    cancelled: &AtomicBool,
) -> Result<OpenRouterInferenceProvider, String> {
    let key = login
        .complete(cancelled)
        .map_err(|error| error.to_string())?;
    connect_with_key(key, cancelled)
}

fn ensure_not_cancelled(cancelled: &AtomicBool) -> Result<(), String> {
    if cancelled.load(Ordering::Acquire) {
        Err("Connection cancelled".to_string())
    } else {
        Ok(())
    }
}
