defmodule ConduktSiteWeb.PageController do
  use ConduktSiteWeb, :controller

  def home(conn, _params) do
    conn
    |> assign(:page_title, "One agent. Every surface.")
    |> assign(:connected, not is_nil(get_session(conn, :openrouter_key)))
    |> assign(:inference_model, Application.fetch_env!(:condukt_site, :openrouter_model))
    |> render(:home)
  end
end
