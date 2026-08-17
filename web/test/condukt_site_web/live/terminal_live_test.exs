defmodule ConduktSiteWeb.TerminalLiveTest do
  use ConduktSiteWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias ConduktSite.Repository

  @declaration %{
    "name" => "list_repository_directory",
    "description" => "List a directory in the repository.",
    "parameters" => %{"type" => "object", "properties" => %{}}
  }

  defp declare_tools(live) do
    render_hook(live, "tools", %{"tools" => [@declaration]})
    live
  end

  defp session_id(live), do: :sys.get_state(live.pid).socket.assigns.session_id

  describe "before signing in" do
    test "invites the visitor to connect, and says what the agent can reach", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/terminal")

      assert html =~ "Connect OpenRouter"
      assert html =~ Repository.source().repository
      refute html =~ "Ask about Condukt&#39;s source"
    end

    test "offers no way to submit a prompt", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/terminal")

      refute has_element?(live, "#agent-form")
    end

    # Without a credential there is nothing to bill inference to, so a page
    # declaring tools must not bring a session into existence.
    test "declaring tools does not start a session", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/terminal")

      refute session_id(declare_tools(live))
    end
  end

  describe "after signing in" do
    setup %{conn: conn} do
      %{conn: init_test_session(conn, %{"openrouter_key" => "sk-or-v1-test"})}
    end

    test "offers the composer", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/terminal")

      assert has_element?(live, "#agent-form")
      assert has_element?(live, "#agent-prompt")
    end

    # The tools belong to the page, so the session waits for them rather than
    # starting at mount with none.
    test "the session starts when the page declares what it can do", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/terminal")
      refute session_id(live)

      declare_tools(live)

      assert Condukt.Sessions.alive?(session_id(live))
    end

    test "the declared tools are the session's tools", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/terminal")

      tools = :sys.get_state(Condukt.Sessions.whereis(session_id(declare_tools(live)))).tools

      assert [%Condukt.Tool.Inline{name: "list_repository_directory"}] = tools
    end

    # A page whose JavaScript never ran still has a working conversation, just
    # one with nothing to call.
    test "a prompt without declared tools still starts a session", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/terminal")

      render_hook(live, "submit", %{"prompt" => "hello"})

      assert Condukt.Sessions.alive?(session_id(live))
    end

    test "echoes what was asked before the answer arrives", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/terminal")

      html = render_hook(declare_tools(live), "submit", %{"prompt" => "what is in lib?"})

      assert html =~ "what is in lib?"
    end

    test "an empty prompt submits nothing", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/terminal")

      html = render_hook(live, "submit", %{"prompt" => "   "})

      refute html =~ ~s(data-role="user")
    end

    # Streamed text arrives in fragments; one answer should read as one block
    # rather than one entry per token.
    test "assistant fragments join into a single reply", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/terminal")

      send(live.pid, {:agent, {:text, "Condukt "}})
      send(live.pid, {:agent, {:text, "is portable."}})

      assert render(live) =~ "Condukt is portable."
    end

    test "a failed turn is reported rather than left hanging", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/terminal")

      send(live.pid, {:agent, {:error, "the provider refused the key"}})

      assert render(live) =~ "the provider refused the key"
    end

    # A visitor closing the tab must not leave a session running on the server.
    test "the session stops when the visitor leaves", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/terminal")
      id = session_id(declare_tools(live))
      assert Condukt.Sessions.alive?(id)

      GenServer.stop(live.pid)

      refute await_stopped(id)
    end

    # The ordinary ending: a lost connection kills the LiveView outright, so
    # nothing on the way out gets a chance to stop the session.
    test "a dropped connection stops the session too", %{conn: conn} do
      Process.flag(:trap_exit, true)
      {:ok, live, _html} = live(conn, ~p"/terminal")
      id = session_id(declare_tools(live))
      assert Condukt.Sessions.alive?(id)

      Process.exit(live.pid, :kill)

      refute await_stopped(id)
    end
  end

  describe "the browser-tool round trip" do
    setup %{conn: conn} do
      conn = init_test_session(conn, %{"openrouter_key" => "sk-or-v1-test"})
      {:ok, live, _html} = live(conn, ~p"/terminal")
      %{live: declare_tools(live)}
    end

    test "a tool call is pushed to the page and shown as activity", %{live: live} do
      send(live.pid, {:browser_tool, self(), make_ref(), "list_repository_directory", %{}})

      assert_push_event(live, "condukt:tool", %{name: "list_repository_directory", token: token})
      assert is_binary(token)
      assert render(live) =~ "list_repository_directory"
    end

    test "the page's answer reaches the process waiting for it", %{live: live} do
      ref = make_ref()
      send(live.pid, {:browser_tool, self(), ref, "list_repository_directory", %{}})
      assert_push_event(live, "condukt:tool", %{token: token})

      render_hook(live, "tool_result", %{"token" => token, "ok" => true, "result" => %{"a" => 1}})

      assert_receive {:browser_tool_result, ^ref, {:ok, %{"a" => 1}}}
    end

    test "an error from the page reaches the caller as an error", %{live: live} do
      ref = make_ref()
      send(live.pid, {:browser_tool, self(), ref, "list_repository_directory", %{}})
      assert_push_event(live, "condukt:tool", %{token: token})

      render_hook(live, "tool_result", %{
        "token" => token,
        "error" => "GitHub returned status 404"
      })

      assert_receive {:browser_tool_result, ^ref, {:error, "GitHub returned status 404"}}
    end

    test "a malformed answer is reported rather than passed to the agent", %{live: live} do
      ref = make_ref()
      send(live.pid, {:browser_tool, self(), ref, "list_repository_directory", %{}})
      assert_push_event(live, "condukt:tool", %{token: token})

      render_hook(live, "tool_result", %{"token" => token, "ok" => "yes"})

      assert_receive {:browser_tool_result, ^ref, {:error, message}}
      assert message =~ "malformed"
    end

    # The pending calls live in this LiveView's own state, so a client cannot
    # answer a call that was never made, nor one belonging to anybody else.
    test "a result for an unknown token is dropped", %{live: live} do
      render_hook(live, "tool_result", %{
        "token" => "not-a-real-token",
        "ok" => true,
        "result" => 1
      })

      refute_receive {:browser_tool_result, _ref, _result}
      assert render(live)
    end

    test "a token cannot be replayed to answer the same call twice", %{live: live} do
      ref = make_ref()
      send(live.pid, {:browser_tool, self(), ref, "list_repository_directory", %{}})
      assert_push_event(live, "condukt:tool", %{token: token})

      answer = %{"token" => token, "ok" => true, "result" => 1}
      render_hook(live, "tool_result", answer)
      assert_receive {:browser_tool_result, ^ref, _result}

      render_hook(live, "tool_result", answer)

      refute_receive {:browser_tool_result, ^ref, _result}
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
