defmodule ConduktSiteWeb.TerminalLiveTest do
  use ConduktSiteWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias ConduktSite.Repository

  describe "before signing in" do
    test "invites the visitor to connect, and says what the agent can reach", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/terminal")

      assert html =~ "Connect OpenRouter"
      assert html =~ Repository.source().repository
      refute html =~ "Ask about Condukt&#39;s source"
    end

    test "offers no way to submit a prompt", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/terminal")

      refute has_element?(live, "form")
    end
  end

  describe "after signing in" do
    setup %{conn: conn} do
      %{conn: init_test_session(conn, %{"openrouter_key" => "sk-or-v1-test"})}
    end

    test "starts a real session on the server", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/terminal")

      session_id = :sys.get_state(live.pid).socket.assigns.session_id

      assert is_binary(session_id)
      assert Condukt.Sessions.alive?(session_id)
    end

    test "offers the prompt", %{conn: conn} do
      {:ok, live, html} = live(conn, ~p"/terminal")

      assert has_element?(live, "form")
      assert html =~ "Ask about Condukt"
    end

    test "echoes what was asked before the answer arrives", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/terminal")

      html =
        live
        |> form("form", %{"prompt" => "what is in lib?"})
        |> render_submit()

      assert html =~ "what is in lib?"
    end

    test "an empty prompt submits nothing", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/terminal")

      html = live |> form("form", %{"prompt" => "   "}) |> render_submit()

      refute html =~ ~s(data-kind="prompt")
    end

    # Streamed text arrives in fragments; one answer should read as one block
    # rather than one entry per token.
    test "assistant fragments join into a single reply", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/terminal")

      send(live.pid, {:agent, {:text, "Condukt "}})
      send(live.pid, {:agent, {:text, "is portable."}})

      assert render(live) =~ "Condukt is portable."
    end

    test "a tool call is shown as activity", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/terminal")

      send(live.pid, {:agent, {:tool_call, "read_repository_file", "call-1", %{}}})

      assert render(live) =~ "read_repository_file"
    end

    test "a failed turn is reported rather than left hanging", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/terminal")

      send(live.pid, {:agent, {:error, "the provider refused the key"}})

      assert render(live) =~ "the provider refused the key"
    end

    # A visitor closing the tab must not leave a session running on the server.
    test "the session stops when the visitor leaves", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/terminal")
      session_id = :sys.get_state(live.pid).socket.assigns.session_id
      assert Condukt.Sessions.alive?(session_id)

      GenServer.stop(live.pid)

      refute await_stopped(session_id)
    end
  end

  defp await_stopped(session_id, remaining \\ 500)

  defp await_stopped(session_id, remaining) when remaining <= 0,
    do: Condukt.Sessions.alive?(session_id)

  defp await_stopped(session_id, remaining) do
    if Condukt.Sessions.alive?(session_id) do
      Process.sleep(10)
      await_stopped(session_id, remaining - 10)
    else
      false
    end
  end
end
