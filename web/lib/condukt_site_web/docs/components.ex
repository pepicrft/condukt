defmodule ConduktSiteWeb.Docs.Components do
  @moduledoc "Shared navigation, sidebar, and table-of-contents components for documentation."

  use ConduktSiteWeb, :html

  alias ConduktSiteWeb.Docs.Navigation

  attr :current_slug, :string, required: true
  attr :tab, :atom, required: true
  attr :headings, :list, required: true
  attr :markdown, :string, required: true
  slot :inner_block, required: true

  def docs_layout(assigns) do
    assigns = assign(assigns, :tree, Navigation.tree_for_tab(assigns.tab))

    ~H"""
    <condukt-docs-shell id="docs-shell">
      <a data-part="docs-skip-link" href="#docs-content">Skip to content</a>

      <nav id="docs-nav" aria-label="Documentation navigation">
        <div data-part="docs-nav-header">
          <a href={~p"/"} data-part="docs-logo-link" aria-label="Condukt home">
            <span data-part="brand-mark" aria-hidden="true">
              <span></span><span></span><span></span>
            </span>
            <span data-part="docs-logo-divider"></span>
            <span data-part="docs-logo-text">Docs</span>
          </a>

          <div data-part="docs-tabs" aria-label="Documentation sections">
            <a
              href={~p"/docs/guide"}
              data-part="docs-tab"
              data-selected={@tab == :use_condukt}
            >
              Use Condukt
            </a>
            <a
              href={~p"/docs/reference"}
              data-part="docs-tab"
              data-selected={@tab == :build_agents}
            >
              Build agents
            </a>
          </div>
        </div>

        <a
          data-part="docs-social-link"
          href="https://github.com/tuist/condukt"
          target="_blank"
          rel="noreferrer"
          aria-label="View Condukt on GitHub"
        >
          <noora-icon name="brand_github" label="GitHub" size="20"></noora-icon>
        </a>
      </nav>

      <div id="docs-mobile-menu-bar" role="toolbar" aria-label="Page navigation">
        <noora-button
          id="docs-menu-trigger"
          variant="secondary"
          size="small"
          aria-controls="docs-sidebar"
          aria-expanded="false"
        >
          <noora-icon name="menu_3" label="" size="16"></noora-icon>
          Menu
        </noora-button>
        <noora-button
          :if={@headings != []}
          id="docs-toc-trigger"
          variant="secondary"
          size="small"
          aria-controls="docs-mobile-toc"
          aria-expanded="false"
        >
          On this page
          <noora-icon name="news" label="" size="16"></noora-icon>
        </noora-button>
      </div>

      <button
        id="docs-sidebar-overlay"
        type="button"
        aria-label="Close documentation menu"
        tabindex="-1"
      >
      </button>

      <main id="docs-page-layout">
        <textarea :if={@markdown != ""} id="docs-page-markdown" hidden readonly>{@markdown}</textarea>

        <nav
          :if={@headings != []}
          id="docs-mobile-toc"
          data-state="closed"
          aria-label="Table of contents"
        >
          <a href="#docs-content" data-part="docs-mobile-toc-item">Return to top</a>
          <a
            :for={heading <- @headings}
            href={"##{heading.id}"}
            data-part="docs-mobile-toc-item"
            data-level={heading.level}
          >
            {heading.text}
          </a>
        </nav>

        <div id="docs-layout">
          <nav id="docs-sidebar" aria-label="Documentation pages">
            <div data-part="docs-sidebar-scroll">
              <a
                href={~p"/docs"}
                data-part="docs-sidebar-link"
                data-selected={@current_slug == "/docs"}
              >
                <span class="noora-tab-menu-vertical" data-selected={@current_slug == "/docs"}>
                  <span data-part="icon-left">
                    <noora-icon name="smart_home" label="" size="18"></noora-icon>
                  </span>
                  <span data-part="label">Documentation home</span>
                </span>
              </a>

              <div data-part="docs-mobile-journeys" aria-label="Documentation journeys">
                <a href={~p"/docs/guide"} data-selected={@tab == :use_condukt}>Use Condukt</a>
                <a href={~p"/docs/reference"} data-selected={@tab == :build_agents}>
                  Build agents
                </a>
              </div>

              <section :for={group <- @tree} data-part="docs-nav-section">
                <div data-part="docs-section-heading">
                  <span data-part="docs-section-icon">
                    <noora-icon name={group.icon} label="" size="20"></noora-icon>
                  </span>
                  <span>{group.label}</span>
                </div>
                <div data-part="docs-nav-items">
                  <a
                    :for={item <- group.items}
                    href={item.slug}
                    data-part="docs-sidebar-link"
                    data-selected={item.slug == @current_slug}
                  >
                    <span
                      class="noora-tab-menu-vertical"
                      data-selected={item.slug == @current_slug}
                    >
                      <span data-part="label">{item.label}</span>
                    </span>
                  </a>
                </div>
              </section>
            </div>
          </nav>

          <div id="docs-content">
            <div :if={@markdown != ""} data-part="docs-mobile-copy">
              <noora-button data-copy-page variant="secondary" size="small">Copy page</noora-button>
            </div>
            {render_slot(@inner_block)}
          </div>

          <aside :if={@headings != []} id="docs-toc" aria-label="Table of contents">
            <noora-button
              :if={@markdown != ""}
              data-copy-page
              variant="secondary"
              size="small"
            >
              Copy page
            </noora-button>
            <div data-part="docs-toc-heading">
              <noora-icon name="list_tree" label="" size="16"></noora-icon>
              <span>On this page</span>
            </div>
            <ul>
              <li :for={heading <- @headings}>
                <a href={"##{heading.id}"} data-level={heading.level}>{heading.text}</a>
              </li>
            </ul>
          </aside>
        </div>
      </main>
    </condukt-docs-shell>
    """
  end

  def docs_markdown_path("/docs/" <> rest), do: "/docs-markdown/" <> rest
  def docs_markdown_path(_), do: "/docs-markdown"

  def docs_edit_path(source_path) when is_binary(source_path) do
    "https://github.com/tuist/condukt/edit/main/web/priv/docs/#{source_path}"
  end

  def docs_edit_path(_), do: "https://github.com/tuist/condukt/tree/main/web/priv/docs"
end
