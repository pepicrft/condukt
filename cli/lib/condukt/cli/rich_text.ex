defmodule Condukt.CLI.RichText do
  @moduledoc """
  Inline text with semantic annotations.

  A rich text value is a sequence of annotated chunks. The renderer maps each
  annotation to a style, which lets callers express intent ("this is a command")
  without hard-coding a colour, and lets the theme decide how each kind looks.
  """

  alias Condukt.CLI.Theme
  alias ExRatatui.Style
  alias ExRatatui.Text.Line
  alias ExRatatui.Text.Span

  defstruct chunks: []

  @doc "An empty rich text value."
  def new, do: %__MODULE__{}

  @doc "Appends plain text."
  def push_text(%__MODULE__{} = rich, text), do: push(rich, {:text, text})

  @doc "Appends a slash command, which the theme renders as a verb."
  def push_command(%__MODULE__{} = rich, text), do: push(rich, {:command, text})

  defp push(%__MODULE__{chunks: chunks} = rich, chunk), do: %{rich | chunks: chunks ++ [chunk]}

  @doc "The style for one semantic kind."
  def style(:text), do: %Style{}
  # Plain cyan so the command reads as a verb in the menu without the bold
  # modifier pushing the selected entry into the terminal's bright palette,
  # which many terminals render as white.
  def style(:command), do: Theme.accent_text()

  @doc "Renders the value as a single terminal line."
  def to_line(%__MODULE__{chunks: chunks}) do
    %Line{spans: Enum.map(chunks, fn {kind, text} -> %Span{content: sanitize(text), style: style(kind)} end)}
  end

  @doc """
  Replaces characters a span cannot carry.

  Spans are single-line by construction, so embedded newlines and tabs are
  normalized to spaces rather than raising in the middle of a frame.
  """
  def sanitize(text) do
    text
    |> to_string()
    |> String.replace(["\r\n", "\n", "\r"], " ")
    |> String.replace("\t", "    ")
  end
end
