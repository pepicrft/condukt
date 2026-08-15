defmodule Condukt.CLI.TUITest do
  use ExUnit.Case, async: true

  alias Condukt.CLI.App
  alias Condukt.CLI.Theme
  alias Condukt.CLI.TUI
  alias ExRatatui.Layout.Rect

  @area %Rect{x: 0, y: 0, width: 80, height: 24}

  defp slots(app), do: app |> TUI.layout(@area) |> Enum.map(fn {slot, _rect} -> slot end)

  test "normal mode has a transcript, a prompt, and a footer" do
    slots = slots(App.empty())

    assert :document in slots
    assert :prompt in slots
    assert :footer in slots
    refute :connect_menu in slots
  end

  test "a guided menu replaces the prompt" do
    for mode <- [{:awaiting_connect_method, 0}, {:awaiting_provider, 0}] do
      slots = slots(%{App.empty() | mode: mode})

      assert :connect_menu in slots
      refute :prompt in slots, "the #{inspect(mode)} menu is the input surface"
    end
  end

  test "key entry keeps the prompt" do
    assert :prompt in slots(%{App.empty() | mode: {:awaiting_api_key, "openrouter", false}})
  end

  test "the slash menu sits above the prompt" do
    app = App.recompute_show_commands(%{App.empty() | input: "/"})
    slots = slots(app)

    assert Enum.find_index(slots, &(&1 == :slash_menu)) < Enum.find_index(slots, &(&1 == :prompt))
  end

  test "every slot gets a rectangle inside the frame" do
    app = App.recompute_show_commands(%{App.empty() | input: "/"})

    for {_slot, rect} <- TUI.layout(app, @area) do
      assert rect.width == @area.width
      assert rect.y + rect.height <= @area.height
    end
  end

  test "the progress segment moves along the rule and keeps its width" do
    first = TUI.progress_line(20, 0)
    later = TUI.progress_line(20, 400)

    assert width(first) == 20
    assert width(later) == 20
    assert text(first) != text(later)
    assert Enum.any?(first.spans, &(&1.style == Theme.activity_marker()))
  end

  test "a zero-width rule renders nothing" do
    assert TUI.progress_line(0, 100).spans == []
  end

  test "the prompt line carries its marker, the typed text, and a cursor" do
    line = TUI.prompt_line(%{App.empty() | input: "hello"})

    assert text(line) == "> hello "
    assert List.last(line.spans).style.modifiers == [:reversed]
  end

  test "the prompt content is measured in terminal columns" do
    assert TUI.prompt_content_width(%{App.empty() | input: "é你"}) == 5
  end

  # Layout assertions above check which slot gets which rectangle. These draw
  # the frame for real and read the cells back, which is the only way to catch
  # text landing somewhere other than the slot it was meant for.
  describe "the drawn frame" do
    test "typed text lands inside the prompt, never on the footer" do
      rows = draw(input: "hello world")

      prompt = row_containing(rows, "> hello world")
      [top, bottom] = border_rows(rows)

      assert prompt > top and prompt < bottom, "the prompt content belongs between its rules"
      refute List.last(rows) =~ "hello world", "the footer is not the prompt"
    end

    test "the footer holds the workspace and the model on the last row" do
      rows = draw(cwd: "/tmp/demo")
      footer = List.last(rows)

      assert footer =~ "/tmp/demo"
      assert footer =~ "openrouter"
    end

    test "the transcript sits above the prompt" do
      rows = draw([])
      [top, _bottom] = border_rows(rows)

      assert row_containing(rows, "Type /connect") < top
    end

    test "the slash menu opens between the transcript and the prompt" do
      rows = draw(input: "/")
      [top, _bottom] = border_rows(rows)

      menu = row_containing(rows, "List workspace files")
      assert menu < top
      assert row_containing(rows, "Type /connect") < menu
    end

    test "a guided menu replaces the prompt rather than stacking on it" do
      rows = draw(mode: {:awaiting_connect_method, 0})

      assert row_containing(rows, "Select authentication method:")
      assert row_containing(rows, "→ Sign in with an account")
      refute Enum.any?(rows, &String.contains?(&1, "> "))
    end

    defp draw(opts) do
      width = Keyword.get(opts, :width, 60)
      height = Keyword.get(opts, :height, 14)

      {:ok, state} =
        TUI.mount(
          cwd: Keyword.get(opts, :cwd, "/tmp/demo"),
          footer_refresh: false,
          restore_session: fn _cwd -> {false, nil, []} end
        )

      app =
        state.app
        |> Map.put(:mode, Keyword.get(opts, :mode, :normal))
        |> Map.put(:input, Keyword.get(opts, :input, ""))
        |> App.recompute_show_commands()

      widgets = TUI.render(%{state | app: app}, %ExRatatui.Frame{width: width, height: height})

      terminal = ExRatatui.init_test_terminal(width, height)
      :ok = ExRatatui.draw(terminal, widgets)

      terminal |> ExRatatui.get_buffer_content() |> String.split("\n")
    end

    defp row_containing(rows, text) do
      index = Enum.find_index(rows, &String.contains?(&1, text))
      assert index, "no row contains #{inspect(text)} in:\n#{Enum.join(rows, "\n")}"
      index
    end

    defp border_rows(rows) do
      rows
      |> Enum.with_index()
      |> Enum.filter(fn {row, _index} -> String.starts_with?(row, "───") end)
      |> Enum.map(fn {_row, index} -> index end)
    end
  end

  describe "running headlessly" do
    setup do
      {:ok, tui} =
        TUI.start_link(
          name: nil,
          test_mode: {80, 24},
          footer_refresh: false,
          restore_session: fn _cwd -> {false, nil, []} end,
          browser: fn _url -> :ok end
        )

      # The interface is linked to the test process, which tears it down when
      # the test ends; an explicit stop in `on_exit` would only race with that.
      {:ok, tui: tui}
    end

    test "the launch frame renders", %{tui: tui} do
      snapshot = ExRatatui.Runtime.snapshot(tui)

      assert snapshot.dimensions == {80, 24}
      refute snapshot.polling_enabled?
      assert snapshot.render_count >= 1
    end

    test "typing redraws without crashing", %{tui: tui} do
      before = ExRatatui.Runtime.snapshot(tui).render_count

      for code <- ["/", "h", "e", "l", "p"] do
        ExRatatui.Runtime.inject_event(tui, %ExRatatui.Event.Key{code: code, kind: "press", modifiers: []})
      end

      assert Process.alive?(tui)
      assert ExRatatui.Runtime.snapshot(tui).render_count > before
    end

    test "every mode produces a drawable frame", %{tui: tui} do
      # Walking the connect flow exercises the menu, key-entry, and busy
      # layouts. A widget the renderer cannot draw would raise inside the
      # server, so surviving the walk is the assertion.
      keys = ["/", "c", "o", "n", "n", "enter", "down", "enter", "esc"]

      for code <- keys do
        ExRatatui.Runtime.inject_event(tui, %ExRatatui.Event.Key{code: code, kind: "press", modifiers: []})
      end

      assert Process.alive?(tui)
    end

    test "the connection in flight is the only one that may connect", %{tui: tui} do
      # Cancelling disowns an attempt but cannot stop the task already running
      # it, so a late reply has to be dropped rather than connect an interface
      # the user backed out of.
      send(tui, {:connection_result, make_ref(), {:ok, self()}})
      inject(tui, "x")
      refute connected?(tui), "a disowned connection result must not connect the interface"

      reference = adopt_connection(tui)
      send(tui, {:connection_result, reference, {:ok, self()}})
      inject(tui, "x")
      assert connected?(tui), "the attempt still in flight must be able to connect"
    end

    test "quitting stops the interface", %{tui: tui} do
      reference = Process.monitor(tui)
      Process.unlink(tui)

      for code <- ["/", "q", "u", "i", "t", "enter"] do
        ExRatatui.Runtime.inject_event(tui, %ExRatatui.Event.Key{code: code, kind: "press", modifiers: []})
      end

      assert_receive {:DOWN, ^reference, :process, ^tui, reason}, 2_000
      assert reason in [:normal, :shutdown]
    end
  end

  defp inject(tui, code) do
    ExRatatui.Runtime.inject_event(tui, %ExRatatui.Event.Key{code: code, kind: "press", modifiers: []})
  end

  # The runtime snapshot deliberately does not carry application state, and
  # there is no buffer read-back from a supervised app, so a state assertion has
  # to reach into the server. Injecting an event first makes sure the message
  # under test has already been handled.
  defp connected?(tui), do: :sys.get_state(tui).user_state.app.connected?

  # Stands in for a connection attempt the interface started, without making the
  # network call that starting one for real would.
  defp adopt_connection(tui) do
    reference = make_ref()
    :sys.replace_state(tui, fn state -> put_in(state.user_state.connect_ref, reference) end)
    reference
  end

  defp text(line), do: Enum.map_join(line.spans, & &1.content)

  defp width(line), do: line |> text() |> String.length()
end
