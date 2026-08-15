defmodule Condukt.CLI.Transcript do
  @moduledoc """
  Builders for the lines that make up the conversation document.

  Every entry the interface shows (a user prompt, a model message, a tool call,
  an error) is produced here so the transcript reads consistently no matter
  which part of the application appended it.
  """

  alias Condukt.CLI.RichText
  alias Condukt.CLI.Theme
  alias ExRatatui.Style
  alias ExRatatui.Text.Line
  alias ExRatatui.Text.Span

  @doc "A bare line of unstyled text."
  def plain(text) do
    %Line{spans: [%Span{content: RichText.sanitize(text)}]}
  end

  @doc "A styled single-span line."
  def styled(text, %Style{} = style) do
    %Line{spans: [%Span{content: RichText.sanitize(text), style: style}]}
  end

  @doc "An empty line."
  def blank, do: %Line{spans: []}

  @doc """
  Separates a new activity group from the preceding entry.

  Tool results stay attached to the invocation above them; everything else gets
  a blank line so messages read as blocks rather than one run-on transcript.
  """
  def begin_activity_group(document) do
    case List.last(document) do
      nil -> document
      line -> if blank_line?(line), do: document, else: document ++ [blank()]
    end
  end

  defp blank_line?(%Line{spans: spans}) do
    spans |> Enum.map_join(& &1.content) |> String.trim() == ""
  end

  @doc "The titled header that opens a message block."
  def message_header(label, %Style{} = marker) do
    %Line{
      spans: [
        %Span{content: "▌ ", style: marker},
        %Span{content: RichText.sanitize(label), style: Theme.with_modifier(marker, :bold)}
      ]
    }
  end

  @doc "One body line of a message block, carrying the block's left edge."
  def message_body(content, %Style{} = marker) do
    %Line{
      spans: [
        %Span{content: "▌ ", style: marker},
        %Span{content: RichText.sanitize(content), style: Theme.text()}
      ]
    }
  end

  @doc "Appends a user prompt echo."
  def push_prompt_echo(document, user_name, prompt) do
    document
    |> begin_activity_group()
    |> Kernel.++([message_header(user_name, Theme.user_marker())])
    |> Kernel.++(body_lines(prompt, Theme.user_marker()))
  end

  @doc "Appends a plain informational line."
  def push_info(document, message), do: document ++ [plain(message)]

  @doc """
  Appends a user-visible error as a titled red block.

  Keeping errors in their own activity group makes them readable beside user
  and model messages rather than running into the preceding entry.
  """
  def push_error(document, message) do
    document
    |> begin_activity_group()
    |> Kernel.++([message_header("Error", Theme.error_marker())])
    |> Kernel.++(body_lines(message, Theme.error_marker()))
  end

  @doc "Appends a model message block."
  def push_model_message(document, model_name, text) do
    document
    |> begin_activity_group()
    |> Kernel.++([message_header(model_name, Theme.activity_marker())])
    |> Kernel.++(body_lines(text, Theme.activity_marker()))
  end

  defp body_lines(content, marker) do
    content
    |> to_string()
    |> String.split("\n")
    |> Enum.map(&message_body(&1, marker))
  end

  @doc "A tool invocation: the name in the accent colour, the arguments dimmed."
  def tool_call_line(name, arguments) do
    %Line{
      spans: [
        %Span{content: "▌ ", style: Theme.activity_marker()},
        %Span{content: "tool #{name}", style: Theme.selected()},
        %Span{content: " " <> summarize_arguments(arguments), style: Theme.muted_italic()}
      ]
    }
  end

  @doc """
  A tool result.

  The body is the first line of the output; errors take the message block's
  left edge and the danger colour so a failure is not mistaken for output.
  """
  def tool_result_line(name, output, error \\ nil)

  def tool_result_line(name, _output, error) when is_binary(error) do
    %Line{
      spans: [
        %Span{content: "▌ ", style: Theme.error_marker()},
        %Span{content: RichText.sanitize(name), style: Theme.muted_text()},
        %Span{content: " "},
        %Span{content: truncate_for_display(error, 240), style: Theme.error_text()}
      ]
    }
  end

  def tool_result_line(name, output, nil) do
    first_line = output |> to_string() |> String.split("\n") |> List.first() |> Kernel.||("")

    %Line{
      spans: [
        %Span{content: "┆ ", style: Theme.muted_text()},
        %Span{content: RichText.sanitize(name), style: Theme.muted_text()},
        %Span{content: " "},
        %Span{content: RichText.sanitize(first_line), style: Theme.muted_text()}
      ]
    }
  end

  defp summarize_arguments(arguments) do
    arguments
    |> render_arguments()
    |> String.trim()
    |> truncate(200)
  end

  defp render_arguments(arguments) when is_binary(arguments), do: arguments

  # Tool arguments reach the transcript as decoded JSON, so they always encode
  # back. Anything else is shown as a term rather than risking the frame.
  defp render_arguments(arguments) when is_map(arguments) or is_list(arguments), do: JSON.encode!(arguments)

  defp render_arguments(arguments), do: inspect(arguments)

  defp truncate_for_display(input, max) do
    input |> to_string() |> String.replace("\n", " ") |> truncate(max)
  end

  @doc "Truncates to a character budget, appending an ellipsis when it cut."
  def truncate(input, max_characters) do
    if String.length(input) > max_characters do
      String.slice(input, 0, max_characters) <> "…"
    else
      input
    end
  end
end
