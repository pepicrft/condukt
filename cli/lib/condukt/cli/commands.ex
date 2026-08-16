defmodule Condukt.CLI.Commands do
  @moduledoc """
  Canonical metadata and parsing for interactive slash commands.

  One table drives the menu, the help text, and command dispatch, so the three
  can never disagree about which commands exist.
  """

  @commands [
    %{kind: :connect, name: "connect", usage: "/connect", description: "Connect OpenRouter"},
    %{kind: :files, name: "files", usage: "/files", description: "List workspace files"},
    %{kind: :help, name: "help", usage: "/help", description: "Show available commands"},
    %{kind: :image, name: "image", usage: "/image <path>", description: "Attach an image to the prompt"},
    %{kind: :quit, name: "quit", usage: "/quit", description: "Exit Condukt"},
    %{kind: :read, name: "read", usage: "/read <path>", description: "Read a workspace file"}
  ]

  @doc "Every slash command, in menu order."
  def all, do: @commands

  @doc """
  Parses typed input into a command and its argument.

  Returns `{:ok, command, argument}` or `:error` for anything that is not a
  known command. The argument keeps its internal spaces so `/read a/my file.ex`
  resolves to the path the user typed.
  """
  def parse("/" <> command) do
    {name, argument} =
      case String.split(command, ~r/\s/, parts: 2) do
        [name, argument] -> {name, String.trim(argument)}
        [name] -> {name, ""}
      end

    case Enum.find(@commands, &(&1.name == name)) do
      nil -> :error
      definition -> {:ok, definition, argument}
    end
  end

  def parse(_input), do: :error

  @doc "One-line summary of every command, generated from the table."
  def help_text do
    "Commands: " <> Enum.map_join(@commands, ", ", & &1.usage)
  end

  @doc """
  Filters commands by a fuzzy query, best match first.

  An empty query returns every command in table order.
  """
  def filter(""), do: @commands

  def filter(query) do
    @commands
    |> Enum.map(fn command -> {score("/#{command.name} #{command.description}", query), command} end)
    |> Enum.reject(fn {score, _command} -> is_nil(score) end)
    |> Enum.sort_by(fn {score, _command} -> -score end)
    |> Enum.map(fn {_score, command} -> command end)
  end

  @doc """
  Scores a subsequence match of `query` inside `candidate`.

  Returns `nil` when the query is not a subsequence. Consecutive matches and
  matches at a word boundary score higher, which is what makes `"fi"` rank
  `/files` above a command that merely contains both letters.
  """
  def score(candidate, query) do
    match(graphemes(candidate), graphemes(query), 0, 0, true)
  end

  defp graphemes(text) do
    text |> String.downcase() |> String.graphemes()
  end

  defp match(_candidate, [], score, _index, _boundary?), do: score

  defp match([], _query, _score, _index, _boundary?), do: nil

  defp match([character | candidate], [wanted | query], score, index, boundary?) do
    if character == wanted do
      bonus = if boundary?, do: 8, else: 0
      match(candidate, query, score + 16 + bonus - index, 0, word_boundary?(character))
    else
      match(candidate, [wanted | query], score, min(index + 1, 8), word_boundary?(character))
    end
  end

  defp word_boundary?(character), do: character in [" ", "/", "-", "_", "."]
end
