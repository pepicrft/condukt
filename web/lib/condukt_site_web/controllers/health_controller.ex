defmodule ConduktSiteWeb.HealthController do
  @moduledoc "Readiness endpoint used by the Kubernetes probes."

  use ConduktSiteWeb, :controller

  def ready(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "ok")
  end
end
