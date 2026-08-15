defmodule Condukt.CLI.Syntax do
  @moduledoc """
  Terminal colouring for the Markdown a model writes.

  Fenced code and unified diffs are the two things worth colouring in a final
  response; ordinary prose is left exactly as the model wrote it. Diffs get
  their conventional per-line colours. Other fences get a language-agnostic
  pass over comments, strings, and numbers, which is what carries most of the
  legibility in a short snippet without shipping a grammar per language.
  """

  @reset "\e[0m"
  @added "\e[32m"
  @removed "\e[31m"
  @context "\e[2;37m"
  @header "\e[36m"
  @comment "\e[2;37m"
  @string "\e[33m"
  @number "\e[35m"
  @keyword "\e[36m"

  @diff_languages ~w(diff patch udiff)

  @keywords ~w(
    and as assert async await begin break case catch class const continue def defer defmodule defp
    do elif else end enum export extends fn for from func function if impl import in interface let
    loop match mod module mut new nil not or package pub raise rescue return self static struct
    switch then this throw trait try type use var when where while with yield
  )

  @doc "Highlights fenced code and diff blocks, leaving ordinary Markdown alone."
  def highlight_markdown(markdown) do
    markdown
    |> String.split("\n")
    |> Enum.reduce({[], nil, []}, &consume_line/2)
    |> finish()
  end

  defp consume_line(line, {rendered, nil, _code}) do
    if String.starts_with?(String.trim_trailing(line), "```") do
      {[line | rendered], fence_language(line), []}
    else
      {[line | rendered], nil, []}
    end
  end

  defp consume_line(line, {rendered, language, code}) do
    if String.starts_with?(String.trim_trailing(line), "```") do
      highlighted = code |> Enum.reverse() |> Enum.join("\n") |> highlight_block(language)
      {[line, highlighted | rendered], nil, []}
    else
      {rendered, language, [line | code]}
    end
  end

  defp finish({rendered, nil, _code}), do: rendered |> Enum.reverse() |> Enum.join("\n")

  defp finish({rendered, language, code}) do
    highlighted = code |> Enum.reverse() |> Enum.join("\n") |> highlight_block(language)
    [highlighted | rendered] |> Enum.reverse() |> Enum.join("\n")
  end

  defp fence_language(line) do
    line |> String.trim_trailing() |> String.trim_leading("`") |> String.trim() |> String.downcase()
  end

  @doc "Highlights one fenced block for a language."
  def highlight_block(code, language) when language in @diff_languages, do: highlight_diff(code)

  def highlight_block(code, _language) do
    code |> String.split("\n") |> Enum.map_join("\n", &highlight_code_line/1)
  end

  @doc "Colours a unified diff the conventional way."
  def highlight_diff(diff) do
    diff
    |> String.split("\n")
    |> Enum.map_join("\n", fn line -> colorize(line, diff_color(line)) end)
  end

  defp diff_color("+++" <> _rest), do: @header
  defp diff_color("---" <> _rest), do: @header
  defp diff_color("@@" <> _rest), do: @header
  defp diff_color("+" <> _rest), do: @added
  defp diff_color("-" <> _rest), do: @removed
  defp diff_color(_line), do: @context

  defp colorize("", _color), do: ""
  defp colorize(text, color), do: color <> text <> @reset

  defp highlight_code_line(line) do
    case comment_split(line) do
      {code, comment} -> highlight_tokens(code) <> colorize(comment, @comment)
      nil -> highlight_tokens(line)
    end
  end

  # A comment marker inside a string is not a comment. Scanning for the first
  # marker that is not quoted keeps `url = "https://example.com"` intact.
  defp comment_split(line) do
    graphemes = String.graphemes(line)

    Enum.find_value(["#", "//", "--"], fn marker ->
      case unquoted_index(graphemes, String.graphemes(marker), nil, 0) do
        nil -> nil
        index -> String.split_at(line, index)
      end
    end)
  end

  defp unquoted_index([], _marker, _quote_character, _index), do: nil

  defp unquoted_index([grapheme | rest], marker, nil, index) do
    cond do
      List.starts_with?([grapheme | rest], marker) -> index
      grapheme in ["\"", "'", "`"] -> unquoted_index(rest, marker, grapheme, index + 1)
      true -> unquoted_index(rest, marker, nil, index + 1)
    end
  end

  defp unquoted_index([grapheme | rest], marker, quote_character, index) do
    closing = if grapheme != quote_character, do: quote_character
    unquoted_index(rest, marker, closing, index + 1)
  end

  defp highlight_tokens(code) do
    Regex.replace(~r/("[^"]*"|'[^']*')|\b(\d+(?:\.\d+)?)\b|\b([a-z_]+)\b/u, code, fn
      _match, string, "", "" -> colorize(string, @string)
      _match, "", number, "" -> colorize(number, @number)
      _match, "", "", word -> if word in @keywords, do: colorize(word, @keyword), else: word
      match, _string, _number, _word -> match
    end)
  end
end
