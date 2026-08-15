defmodule Condukt.CLI.InputTest do
  use ExUnit.Case, async: true

  alias Condukt.CLI.App
  alias Condukt.CLI.Input
  alias ExRatatui.Event.Key

  defp key(code, modifiers \\ []), do: %Key{code: code, kind: "press", modifiers: modifiers}

  defp press(app, code, modifiers \\ []) do
    {_status, app, _effects} = Input.handle_key(app, key(code, modifiers))
    app
  end

  defp document_text(app) do
    Enum.map_join(app.document, "\n", fn line -> Enum.map_join(line.spans, & &1.content) end)
  end

  describe "escape" do
    test "clears pending input" do
      app = press(%{App.empty() | input: "hello", show_commands: true, slash_selected: 0}, "esc")

      assert app.input == ""
      refute app.show_commands
      assert app.slash_selected == nil
    end

    test "cancels key entry" do
      app = press(%{App.empty() | mode: {:awaiting_api_key, "openrouter", false}}, "esc")

      assert App.normal?(app)
      assert document_text(app) =~ "Connection cancelled"
    end

    test "cancels a connection in flight" do
      {status, app, effects} = Input.handle_key(%{App.empty() | mode: :connecting}, key("esc"))

      assert status == :continue
      assert App.normal?(app)
      assert effects == [:cancel_connection]
    end

    test "cancels a selection menu" do
      app = press(%{App.empty() | mode: {:awaiting_connect_method, 0}}, "esc")

      assert App.normal?(app)
      assert document_text(app) =~ "Cancelled."
    end

    test "with nothing pending it does nothing" do
      {status, app, effects} = Input.handle_key(App.empty(), key("esc"))

      assert status == :continue
      assert effects == []
      assert app.document == []
    end
  end

  describe "ctrl+c" do
    test "clears pending input without leaving" do
      {status, app, _effects} = Input.handle_key(%{App.empty() | input: "hello"}, key("c", ["ctrl"]))

      assert status == :continue
      assert app.input == ""
    end

    test "cancels an ongoing flow without leaving" do
      {status, app, _effects} =
        Input.handle_key(%{App.empty() | mode: {:awaiting_provider, 0}}, key("c", ["ctrl"]))

      assert status == :continue
      assert App.normal?(app)
    end

    test "with nothing pending it leaves" do
      {status, app, effects} = Input.handle_key(App.empty(), key("c", ["ctrl"]))

      assert status == :stop
      assert app.should_exit
      assert effects == [:exit]
    end
  end

  describe "routing" do
    test "typing builds up the prompt" do
      app = App.empty() |> press("h") |> press("i")
      assert app.input == "hi"
    end

    test "backspace trims the prompt" do
      assert press(%{App.empty() | input: "hi"}, "backspace").input == "h"
      assert press(App.empty(), "backspace").input == ""
    end

    test "a slash opens the menu and a non-matching query closes it" do
      app = press(App.empty(), "/")
      assert app.show_commands
      assert app.slash_selected == 0

      app = app |> press("z") |> press("z") |> press("z")
      refute app.show_commands
    end

    test "arrow keys navigate a menu" do
      app = %{App.empty() | mode: {:awaiting_connect_method, 0}}
      assert press(app, "down").mode == {:awaiting_connect_method, 1}
      assert app |> press("down") |> press("up") |> Map.fetch!(:mode) == {:awaiting_connect_method, 0}
    end

    test "enter submits" do
      {status, app, effects} = Input.handle_key(%{App.empty() | input: "/quit"}, key("enter"))

      assert status == :stop
      assert app.should_exit
      assert effects == [:exit]
    end

    test "the page keys scroll the transcript" do
      app = %{App.empty() | document: Enum.map(1..10, fn index -> line("row #{index}") end)}

      assert app |> press("page_up") |> App.document_scroll(2) == 5
      assert app |> press("page_up") |> press("page_down") |> App.document_scroll(2) == 8
    end

    test "an unbound chord does not type its letter" do
      assert press(App.empty(), "a", ["ctrl"]).input == ""
      assert press(App.empty(), "a", ["alt"]).input == ""
      assert press(App.empty(), "A", ["shift"]).input == "A"
    end

    test "key releases are ignored" do
      {_status, app, _effects} =
        Input.handle_key(App.empty(), %Key{code: "a", kind: "release", modifiers: []})

      assert app.input == ""
    end

    test "input is read-only while a request is in flight" do
      app = %{App.empty() | pending: true, input: "typed"}

      assert press(app, "a").input == "typed"
      assert press(app, "backspace").input == "typed"
      assert press(app, "enter").input == "typed"
    end
  end

  defp line(content) do
    %ExRatatui.Text.Line{spans: [%ExRatatui.Text.Span{content: content}]}
  end
end
