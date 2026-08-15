defmodule Condukt.CLI.Input do
  @moduledoc """
  Translates key presses into interface transitions.

  Returns `{:continue, app, effects}` while the interface should keep running
  and `{:stop, app, effects}` when the user asked to leave.
  """

  alias Condukt.CLI.App
  alias ExRatatui.Event.Key

  @chord_modifiers ["ctrl", "alt", "super"]
  @busy_ignored ["up", "down", "enter", "backspace"]

  @doc "Handles one key event."
  def handle_key(%App{} = app, %Key{kind: kind}) when kind not in ["press", "repeat", nil] do
    {:continue, app, []}
  end

  def handle_key(%App{} = app, %Key{code: code, modifiers: modifiers}) do
    case binding(code, modifiers || []) do
      :interrupt -> handle_ctrl_c(app)
      :cancel -> handle_escape(app)
      :paste -> {:continue, app, [:paste_clipboard]}
      :ignore -> {:continue, app, []}
      :input -> handle_input(app, code)
    end
  end

  def handle_key(%App{} = app, _event), do: {:continue, app, []}

  # The terminal's own paste sends text through a bracketed-paste event and
  # cannot carry an image at all, so an explicit binding is what makes the
  # clipboard's image reachable.
  defp binding("v", modifiers) do
    if "ctrl" in modifiers, do: :paste, else: typed(modifiers)
  end

  defp binding("c", modifiers) do
    if "ctrl" in modifiers, do: :interrupt, else: typed(modifiers)
  end

  defp binding("esc", _modifiers), do: :cancel

  defp binding(_code, modifiers), do: typed(modifiers)

  # A chord the interface does not bind should do nothing rather than insert its
  # letter into the prompt. Shift is not a chord: it is how the character was
  # typed in the first place.
  defp typed(modifiers) do
    if Enum.any?(modifiers, &(&1 in @chord_modifiers)), do: :ignore, else: :input
  end

  # While a request is in flight the interface stays read-only apart from the
  # cancel keys, so a stray keystroke cannot reorder the conversation or start a
  # second turn.
  defp handle_input(app, code) do
    if App.busy?(app) and code in @busy_ignored do
      {:continue, app, []}
    else
      dispatch(app, code)
    end
  end

  @doc """
  Handles Escape.

  Escape clears the input, cancels the active flow, or does nothing. It never
  leaves the interface.
  """
  def handle_escape(%App{} = app) do
    case clear_or_cancel(app) do
      :noop -> {:continue, app, []}
      {app, effects} -> {:continue, app, effects}
    end
  end

  @doc """
  Handles Ctrl+C.

  It behaves like Escape whenever there is something to clear or a flow to
  cancel, and only leaves when nothing is pending.
  """
  def handle_ctrl_c(%App{} = app) do
    case clear_or_cancel(app) do
      :noop -> {:stop, %{app | should_exit: true}, [:exit]}
      {app, effects} -> {:continue, app, effects}
    end
  end

  @doc """
  Clears the input or cancels the active flow.

  Returns `:noop` when there was nothing to do, which is what tells Ctrl+C it
  should leave and Escape that it should do nothing.
  """
  def clear_or_cancel(%App{} = app) do
    cond do
      app.input != "" ->
        {%{app | input: "", show_commands: false, slash_selected: nil}, []}

      App.connecting?(app) ->
        App.cancel_connection(app)

      App.in_menu?(app) ->
        {%{App.push_info(app, "Cancelled.") | mode: :normal}, []}

      App.awaiting_api_key?(app) ->
        {%{App.push_info(app, "Connection cancelled.") | mode: :normal}, []}

      true ->
        :noop
    end
  end

  defp dispatch(app, "up"), do: {:continue, App.select_up(app), []}
  defp dispatch(app, "down"), do: {:continue, App.select_down(app), []}
  defp dispatch(app, "page_up"), do: {:continue, App.scroll_document_up(app), []}
  defp dispatch(app, "page_down"), do: {:continue, App.scroll_document_down(app), []}

  defp dispatch(app, "enter") do
    {app, effects} = App.confirm(app)
    if app.should_exit, do: {:stop, app, effects}, else: {:continue, app, effects}
  end

  defp dispatch(app, "backspace") do
    app = %{app | input: String.slice(app.input, 0..-2//1)}
    {:continue, App.recompute_show_commands(app), []}
  end

  defp dispatch(app, code) when is_binary(code) do
    # Character keys arrive as their own value; every named key is longer than
    # one grapheme, so anything single-width here is text the user typed.
    if String.length(code) == 1 and not App.busy?(app) do
      app = %{app | input: app.input <> code}
      {:continue, App.recompute_show_commands(app), []}
    else
      {:continue, app, []}
    end
  end

  defp dispatch(app, _code), do: {:continue, app, []}
end
