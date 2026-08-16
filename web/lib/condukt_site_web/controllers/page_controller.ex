defmodule ConduktSiteWeb.PageController do
  use ConduktSiteWeb, :controller

  # The terminal is a LiveView now, and it reads the session and the model
  # itself at mount, so neither is assigned here any more.
  def home(conn, _params) do
    conn
    |> assign(:page_title, "One agent. Every surface.")
    |> render(:home)
  end
end
