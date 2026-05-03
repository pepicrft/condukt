defmodule Condukt.Credo.Check.Readability.NoRescue do
  use Credo.Check,
    id: "EXC003",
    base_priority: :high,
    category: :readability,
    explanations: [
      check: """
      Production Elixir code in this repo should avoid `rescue` and new
      `catch` blocks.

      Prefer tuple-returning APIs and pattern matching with `case`,
      `with`, and function heads. If a boundary truly needs to observe
      non-local failures, keep that logic explicit without a local
      `rescue` or `catch` block.
      """
    ]

  alias Credo.IssueMeta
  alias Credo.SourceFile

  @legacy_catch_files ~w(
    lib/condukt/sandbox/local.ex
    lib/condukt/sandbox/virtual.ex
    lib/condukt/session_store/disk.ex
    lib/condukt/telemetry.ex
    lib/condukt/tool.ex
    lib/condukt/tools/command.ex
  )

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params \\ []) do
    if lib_file?(filename) do
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> Credo.Code.ast()
      |> Macro.prewalk([], &walk(&1, &2, issue_meta, filename))
      |> elem(1)
      |> Enum.reverse()
    else
      []
    end
  end

  defp walk({:try, meta, [clauses]} = ast, issues, issue_meta, filename) do
    issues =
      if Keyword.has_key?(clauses, :rescue) do
        [issue_for(issue_meta, meta, :rescue) | issues]
      else
        issues
      end

    issues =
      if Keyword.has_key?(clauses, :catch) and not legacy_catch_file?(filename) do
        [issue_for(issue_meta, meta, :catch) | issues]
      else
        issues
      end

    {ast, issues}
  end

  defp walk(ast, issues, _issue_meta, _filename) do
    {ast, issues}
  end

  defp lib_file?(filename) do
    String.starts_with?(filename, "lib/") or String.contains?(filename, "/lib/")
  end

  defp legacy_catch_file?(filename) do
    filename = Path.expand(filename)

    Enum.any?(@legacy_catch_files, fn path ->
      String.ends_with?(filename, path)
    end)
  end

  defp issue_for(issue_meta, meta, :rescue) do
    format_issue(
      issue_meta,
      message: "Avoid rescue in lib files. Prefer tuple-returning APIs and pattern matching.",
      trigger: "rescue",
      line_no: Keyword.get(meta, :line)
    )
  end

  defp issue_for(issue_meta, meta, :catch) do
    format_issue(
      issue_meta,
      message: "Avoid catch in lib files. Prefer tuple-returning APIs and pattern matching.",
      trigger: "catch",
      line_no: Keyword.get(meta, :line)
    )
  end
end
