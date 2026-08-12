defmodule ConduktSiteWeb.DocsMarkdownController do
  use ConduktSiteWeb, :controller

  alias ConduktSiteWeb.Docs

  def show(conn, %{"path" => segments}) do
    case Docs.source_path(segments) do
      {:ok, file} ->
        conn
        |> put_resp_content_type("text/markdown", "utf-8")
        |> send_file(200, file)

      :error ->
        send_resp(conn, :not_found, "Documentation page not found")
    end
  end
end
