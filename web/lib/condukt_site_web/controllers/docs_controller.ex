defmodule ConduktSiteWeb.DocsController do
  use ConduktSiteWeb, :controller

  alias ConduktSiteWeb.Docs
  alias ConduktSiteWeb.Docs.Navigation

  def index(conn, _params) do
    conn
    |> docs_layout("Documentation")
    |> assign(:current_slug, "/docs")
    |> assign(:tab, :home)
    |> assign(:headings, [])
    |> assign(:markdown, "")
    |> render(:index)
  end

  def show(conn, %{"path" => segments}) do
    current_slug = "/docs/" <> Enum.join(segments, "/")

    case Docs.get_page(segments) do
      {:ok, page} ->
        conn
        |> docs_layout(page.title || "Documentation")
        |> assign(:page, page)
        |> assign(:current_slug, current_slug)
        |> assign(:tab, Navigation.tab_for_slug(current_slug))
        |> assign(:headings, page.headings)
        |> assign(:markdown, page.markdown)
        |> render(:show)

      :error ->
        conn
        |> put_status(:not_found)
        |> docs_layout("Page not found")
        |> assign(:current_slug, current_slug)
        |> assign(:tab, Navigation.tab_for_slug(current_slug))
        |> assign(:headings, [])
        |> assign(:markdown, "")
        |> render(:not_found)
    end
  end

  defp docs_layout(conn, title) do
    conn
    |> put_layout(false)
    |> assign(:docs, true)
    |> assign(:page_title, title)
  end
end
