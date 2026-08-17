defmodule ConduktSiteWeb.HealthControllerTest do
  use ConduktSiteWeb.ConnCase, async: true

  test "GET /ready reports that the release is serving", %{conn: conn} do
    conn = get(conn, ~p"/ready")

    assert text_response(conn, 200) == "ok"
  end
end
