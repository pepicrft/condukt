/// State of the OAuth callback page. The loopback server renders the
/// success or error variant once the user finishes the browser flow.
#[derive(Debug, Clone, Copy)]
pub enum CallbackPage {
    Success,
    Error,
}

/// Build the HTML body for the OAuth callback page. The page is styled
/// with Noora, Tuist's design system. Noora ships a compiled CSS file at
/// `noora/priv/static/noora.css` in the tuist/tuist repo; we load it
/// from jsdelivr so the loopback server doesn't have to bundle assets.
pub fn callback_page(state: CallbackPage) -> String {
    let noora_css = "https://cdn.jsdelivr.net/gh/tuist/tuist@main/noora/priv/static/noora.css";
    let inter = "https://rsms.me/inter/inter.css";

    let (badge, title, body, auto_close) = match state {
        CallbackPage::Success => (
            "success",
            "Signed in",
            "You can close this tab and return to Condukt.",
            true,
        ),
        CallbackPage::Error => (
            "error",
            "Sign-in failed",
            "Something went wrong while completing the sign-in flow. \
             You can close this tab and try again from Condukt.",
            false,
        ),
    };

    let icon = match state {
        CallbackPage::Success => {
            r#"<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg>"#
        }
        CallbackPage::Error => {
            r#"<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"></line><line x1="6" y1="6" x2="18" y2="18"></line></svg>"#
        }
    };

    let auto_close_script = if auto_close {
        // Try to close the tab after a short pause. The browser may
        // refuse if the tab wasn't opened by a script, in which case the
        // "You can close this tab" copy is still visible.
        r#"<script>
            setTimeout(function() {
                try { window.close(); } catch (_) {}
            }, 2500);
        </script>"#
    } else {
        ""
    };

    format!(
        r#"<!DOCTYPE html>
<html lang="en" data-theme="dark">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} · Condukt</title>
<link rel="stylesheet" href="{inter}">
<link rel="stylesheet" href="{noora_css}">
<style>
  :root {{
    color-scheme: dark;
  }}
  html, body {{
    margin: 0;
    padding: 0;
    min-height: 100vh;
    background: var(--noora-surface-background-primary);
    color: var(--noora-surface-label-primary);
    font-family: var(--noora-font-body);
    -webkit-font-smoothing: antialiased;
  }}
  body {{
    display: flex;
    align-items: center;
    justify-content: center;
    padding: var(--noora-spacing-9);
  }}
  .callback-card {{
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--noora-spacing-6);
    max-width: 420px;
    width: 100%;
    padding: var(--noora-spacing-10) var(--noora-spacing-9);
    background: var(--noora-surface-background-secondary);
    border-radius: var(--noora-radius-8);
    box-shadow: var(--noora-border-medium);
    text-align: center;
  }}
  .callback-icon {{
    display: flex;
    align-items: center;
    justify-content: center;
    width: 64px;
    height: 64px;
    border-radius: var(--noora-radius-99);
    padding: var(--noora-spacing-4);
  }}
  .callback-icon svg {{
    width: 32px;
    height: 32px;
  }}
  .callback-icon[data-badge="success"] {{
    background: var(--noora-icon-success-background);
    color: var(--noora-icon-success-label);
  }}
  .callback-icon[data-badge="error"] {{
    background: var(--noora-icon-destructive-background);
    color: var(--noora-icon-destructive-label);
  }}
  .callback-icon[data-badge="success"] svg {{
    animation: callback-icon-pop 400ms var(--ease-out-back, cubic-bezier(0.34, 1.56, 0.64, 1)) both;
  }}
  @keyframes callback-icon-pop {{
    0%   {{ transform: scale(0.4); opacity: 0; }}
    100% {{ transform: scale(1);   opacity: 1; }}
  }}
  h1 {{
    margin: 0;
    font: var(--noora-font-weight-semibold) var(--noora-font-heading-large);
    color: var(--noora-surface-label-primary);
    letter-spacing: -0.01em;
  }}
  p {{
    margin: 0;
    font: var(--noora-font-weight-regular) var(--noora-font-body-medium);
    color: var(--noora-surface-label-secondary);
    line-height: 1.5;
  }}
  .callback-footer {{
    margin-top: var(--noora-spacing-2);
    font: var(--noora-font-weight-medium) var(--noora-font-body-xsmall);
    color: var(--noora-surface-label-tertiary);
    text-transform: uppercase;
    letter-spacing: 0.08em;
  }}
</style>
</head>
<body>
  <main class="callback-card" data-badge="{badge}">
    <div class="callback-icon" data-badge="{badge}" aria-hidden="true">{icon}</div>
    <h1>{title}</h1>
    <p>{body}</p>
    <div class="callback-footer">Condukt</div>
  </main>
  {auto_close_script}
</body>
</html>"#
    )
}
