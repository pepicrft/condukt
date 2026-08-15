defmodule Condukt.CLI.Width do
  @moduledoc """
  Terminal display width of text.

  A terminal cell is not a code point: East Asian wide and fullwidth characters
  occupy two columns, and combining marks occupy none. Cursor placement and
  right-aligned footer text both need columns rather than character counts, so
  the measurement lives here instead of being approximated at each call site.
  """

  @doc "Display width, in terminal columns, of a string."
  def of(text) do
    text
    |> String.to_charlist()
    |> Enum.reduce(0, fn codepoint, width -> width + codepoint_width(codepoint) end)
  end

  @doc """
  Truncates to a column budget, appending an ellipsis when it cut.

  The ellipsis is itself one column, so the result never exceeds `max`.
  """
  def truncate(text, max) when max <= 0, do: if(max == 0, do: "", else: text)

  def truncate(text, 1) do
    if of(text) <= 1, do: text, else: "…"
  end

  def truncate(text, max) do
    if of(text) <= max do
      text
    else
      text |> take_columns(max - 1) |> Kernel.<>("…")
    end
  end

  defp take_columns(text, budget) do
    text
    |> String.to_charlist()
    |> Enum.reduce_while({[], 0}, fn codepoint, {taken, width} ->
      next = width + codepoint_width(codepoint)
      if next > budget, do: {:halt, {taken, width}}, else: {:cont, {[codepoint | taken], next}}
    end)
    |> then(fn {taken, _width} -> taken |> Enum.reverse() |> List.to_string() end)
  end

  # Zero-width: combining marks, zero-width space and joiners, variation selectors.
  defp codepoint_width(codepoint)
       when codepoint in 0x0300..0x036F
       when codepoint in 0x200B..0x200F
       when codepoint in 0xFE00..0xFE0F, do: 0

  # East Asian Wide and Fullwidth ranges.
  defp codepoint_width(codepoint)
       when codepoint in 0x1100..0x115F
       when codepoint in 0x2E80..0x303E
       when codepoint in 0x3041..0x33FF
       when codepoint in 0x3400..0x4DBF
       when codepoint in 0x4E00..0x9FFF
       when codepoint in 0xA000..0xA4CF
       when codepoint in 0xAC00..0xD7A3
       when codepoint in 0xF900..0xFAFF
       when codepoint in 0xFE30..0xFE6F
       when codepoint in 0xFF00..0xFF60
       when codepoint in 0xFFE0..0xFFE6
       when codepoint in 0x1F300..0x1F64F
       when codepoint in 0x1F900..0x1F9FF
       when codepoint in 0x20000..0x3FFFD, do: 2

  defp codepoint_width(_codepoint), do: 1
end
