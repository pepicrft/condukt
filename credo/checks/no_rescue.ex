defmodule Condukt.Credo.Check.Readability.NoRescue do
  use Credo.Check,
    id: "EXC003",
    base_priority: :high,
    category: :readability,
    explanations: [
      check: """
      Production Elixir code in this repo should avoid `rescue`.

      Prefer tuple-returning APIs and pattern matching with `case`,
      `with`, and function heads. If a boundary truly needs to observe
      non-local failures, keep that logic explicit without a `rescue`
      block.
      """
    ]

  alias Credo.IssueMeta
  alias Credo.SourceFile

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params \\ []) do
    if lib_file?(filename) do
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> Credo.Code.ast()
      |> Macro.prewalk([], &walk(&1, &2, issue_meta))
      |> elem(1)
      |> Enum.reverse()
    else
      []
    end
  end

  defp walk({:try, meta, [clauses]} = ast, issues, issue_meta) do
    if Keyword.has_key?(clauses, :rescue) do
      issue = issue_for(issue_meta, meta)
      {ast, [issue | issues]}
    else
      {ast, issues}
    end
  end

  defp walk(ast, issues, _issue_meta) do
    {ast, issues}
  end

  defp lib_file?(filename) do
    String.starts_with?(filename, "lib/") or String.contains?(filename, "/lib/")
  end

  defp issue_for(issue_meta, meta) do
    format_issue(
      issue_meta,
      message: "Avoid rescue in lib files. Prefer tuple-returning APIs and pattern matching.",
      trigger: "rescue",
      line_no: Keyword.get(meta, :line)
    )
  end
end
