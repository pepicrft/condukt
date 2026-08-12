defmodule ConduktSiteWeb.Layouts do
  @moduledoc "Application layouts for the Condukt website."

  use ConduktSiteWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div data-part="site-shell">
      <header data-part="site-header">
        <div data-part="site-header-inner">
          <a href={~p"/"} data-part="brand" aria-label="Condukt home">
            <span data-part="brand-mark" aria-hidden="true">
              <span></span>
              <span></span>
              <span></span>
            </span>
            <span>Condukt</span>
          </a>

          <nav data-part="site-navigation" aria-label="Primary navigation">
            <a data-part="navigation-link" href="#install">Install</a>
            <a data-part="navigation-link" href={~p"/docs"}>Docs</a>
            <a
              data-part="navigation-icon"
              href="https://github.com/tuist/condukt"
              target="_blank"
              rel="noreferrer"
              aria-label="View Condukt on GitHub"
            >
              <noora-icon name="brand_github" label="GitHub"></noora-icon>
            </a>
          </nav>
        </div>
      </header>

      <main data-part="site-main">
        {render_slot(@inner_block)}
      </main>

      <footer data-part="site-footer">
        <p>Released under the MIT License.</p>
        <p>Copyright © Tuist GmbH</p>
      </footer>

      <div data-part="flash-group" aria-live="polite">
        <noora-alert
          :if={message = Phoenix.Flash.get(@flash, :info)}
          type="primary"
          status="success"
          size="medium"
          title={message}
          show-icon
          dismissible
        >
        </noora-alert>
        <noora-alert
          :if={message = Phoenix.Flash.get(@flash, :error)}
          type="primary"
          status="error"
          size="medium"
          title={message}
          show-icon
          dismissible
        >
        </noora-alert>
      </div>
    </div>
    """
  end
end
