defmodule Condukt.CLI.OAuth.CallbackPage do
  @moduledoc """
  The HTML the loopback server renders once the user finishes the browser flow.

  The page is styled with Noora, Tuist's design system. Noora ships a compiled
  stylesheet at `noora/priv/static/noora.css` in the tuist/tuist repository; it
  is loaded from jsDelivr so the loopback server does not have to bundle assets.
  """

  @noora_css "https://cdn.jsdelivr.net/gh/tuist/tuist@main/noora/priv/static/noora.css"
  @inter "https://rsms.me/inter/inter.css"

  @success_icon ~s(<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg>)
  @error_icon ~s(<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"></line><line x1="6" y1="6" x2="18" y2="18"></line></svg>)

  # The browser may refuse to close a tab it did not open by script, in which
  # case the "You can close this tab" copy is still visible.
  @auto_close_script """
  <script>
      setTimeout(function() {
          try { window.close(); } catch (_) {}
      }, 2500);
  </script>
  """

  @doc "Builds the HTML body for either state of the callback page."
  def render(:success) do
    page(
      badge: "success",
      icon: @success_icon,
      title: "Signed in",
      body: "You can close this tab and return to Condukt.",
      script: @auto_close_script
    )
  end

  def render(:error) do
    page(
      badge: "error",
      icon: @error_icon,
      title: "Sign-in failed",
      body:
        "Something went wrong while completing the sign-in flow. You can close this tab and try again from Condukt.",
      script: ""
    )
  end

  defp page(assigns) do
    """
    <!DOCTYPE html>
    <html lang="en" data-theme="dark">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>#{assigns[:title]} · Condukt</title>
    <link rel="stylesheet" href="#{@inter}">
    <link rel="stylesheet" href="#{@noora_css}">
    <style>
      :root {
        color-scheme: dark;
      }
      html, body {
        margin: 0;
        padding: 0;
        min-height: 100vh;
        background: var(--noora-surface-background-primary);
        color: var(--noora-surface-label-primary);
        font-family: var(--noora-font-body);
        -webkit-font-smoothing: antialiased;
      }
      body {
        display: flex;
        align-items: center;
        justify-content: center;
        padding: var(--noora-spacing-9);
      }
      .callback-card {
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
      }
      .callback-icon {
        display: flex;
        align-items: center;
        justify-content: center;
        width: 64px;
        height: 64px;
        border-radius: var(--noora-radius-99);
        padding: var(--noora-spacing-4);
      }
      .callback-icon svg {
        width: 32px;
        height: 32px;
      }
      .callback-icon[data-badge="success"] {
        background: var(--noora-icon-success-background);
        color: var(--noora-icon-success-label);
      }
      .callback-icon[data-badge="error"] {
        background: var(--noora-icon-destructive-background);
        color: var(--noora-icon-destructive-label);
      }
      .callback-icon[data-badge="success"] svg {
        animation: callback-icon-pop 400ms var(--ease-out-back, cubic-bezier(0.34, 1.56, 0.64, 1)) both;
      }
      @keyframes callback-icon-pop {
        0%   { transform: scale(0.4); opacity: 0; }
        100% { transform: scale(1);   opacity: 1; }
      }
      h1 {
        margin: 0;
        font: var(--noora-font-weight-semibold) var(--noora-font-heading-large);
        color: var(--noora-surface-label-primary);
        letter-spacing: -0.01em;
      }
      p {
        margin: 0;
        font: var(--noora-font-weight-regular) var(--noora-font-body-medium);
        color: var(--noora-surface-label-secondary);
        line-height: 1.5;
      }
      .callback-footer {
        margin-top: var(--noora-spacing-2);
        font: var(--noora-font-weight-medium) var(--noora-font-body-xsmall);
        color: var(--noora-surface-label-tertiary);
        text-transform: uppercase;
        letter-spacing: 0.08em;
      }
    </style>
    </head>
    <body>
      <main class="callback-card" data-badge="#{assigns[:badge]}">
        <div class="callback-icon" data-badge="#{assigns[:badge]}" aria-hidden="true">#{assigns[:icon]}</div>
        <h1>#{assigns[:title]}</h1>
        <p>#{assigns[:body]}</p>
        <div class="callback-footer">Condukt</div>
      </main>
      #{assigns[:script]}
    </body>
    </html>
    """
  end
end
