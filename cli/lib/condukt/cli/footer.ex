defmodule Condukt.CLI.Footer do
  @moduledoc """
  A status footer showing the worktree, its branch, and the checks on its pull
  request.

  The data is collected outside the frame loop: `refresh/1` shells out to `git`
  and `gh` from a task, and the interface renders whatever snapshot it last
  received. A failed lookup leaves the previous value in place rather than
  blanking the line, so a momentarily unavailable `gh` does not make the footer
  flicker.
  """

  alias Condukt.CLI.OpenRouter
  alias Condukt.CLI.Theme
  alias Condukt.CLI.Width
  alias ExRatatui.Text.Line
  alias ExRatatui.Text.Span

  @refresh_interval to_timeout(second: 5)
  @command_timeout to_timeout(second: 4)

  defstruct [:working_dir, :branch, :pull_request, :checks]

  @doc "A footer for a working directory, with no data collected yet."
  def new(working_dir), do: %__MODULE__{working_dir: working_dir}

  @doc "How often the interface should ask for a new snapshot."
  def refresh_interval, do: @refresh_interval

  @doc """
  Collects branch, pull request, and check data for a working directory.

  Runs `git` and `gh`, so it belongs in a task rather than the frame loop.
  Returns the fields to merge into the footer.
  """
  def refresh(working_dir) do
    branch = git_branch(working_dir)
    pull_request = branch && gh_pull_request(working_dir, branch)
    checks = pull_request && gh_checks(working_dir, pull_request)

    %{branch: branch, pull_request: pull_request, checks: checks}
  end

  @doc "Applies a snapshot produced by `refresh/1`."
  def apply_refresh(%__MODULE__{} = footer, snapshot), do: struct(footer, snapshot)

  @doc """
  Renders one compact status line.

  Pull-request numbers are deliberately not shown: the check summary is the
  actionable part, and the host application already owns that presentation.
  """
  def lines(%__MODULE__{} = footer, width) do
    left =
      [shorten_path(footer.working_dir) <> " (" <> (footer.branch || "detached") <> ")", format_checks(footer.checks)]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" · ")

    [line_with_right_spans(width, left, model_spans())]
  end

  defp model_spans do
    [%Span{content: "(openrouter) #{OpenRouter.model()} · high", style: Theme.muted_text()}]
  end

  # Builds a line with `left` flush left, `right_spans` flush right, and padding
  # between. The caller owns the right-hand styling so it can carry its own
  # emphasis or hyperlinks.
  defp line_with_right_spans(width, left, right_spans) do
    available = max(width, 0)
    right_width = Enum.reduce(right_spans, 0, fn span, total -> total + Width.of(span.content) end)
    left_width = Width.of(left)

    cond do
      available == 0 ->
        %Line{spans: [%Span{content: left, style: Theme.muted_text()}]}

      left_width + right_width + 1 >= available ->
        %Line{spans: [%Span{content: Width.truncate(left, available), style: Theme.muted_text()}]}

      true ->
        padding = available - left_width - right_width

        %Line{
          spans:
            [%Span{content: left, style: Theme.muted_text()}, %Span{content: String.duplicate(" ", padding)}] ++
              right_spans
        }
    end
  end

  @doc """
  Renders check counts as a short summary.

  Returns `nil` when there are no checks at all so the caller can leave the
  segment out instead of printing a placeholder.
  """
  def format_checks(nil), do: nil

  def format_checks(%{passing: passing, failing: failing, pending: pending}) do
    parts =
      [
        passing > 0 && "✓ #{passing} passing",
        failing > 0 && "✗ #{failing} failing",
        pending > 0 && "⋯ #{pending} pending"
      ]
      |> Enum.filter(&is_binary/1)

    if parts != [], do: "CI: " <> Enum.join(parts, ", ")
  end

  @doc """
  Shortens a path for display: the home directory becomes `~`, and only the last
  two components survive so a deep path cannot eat the footer.
  """
  def shorten_path(path, home \\ System.get_env("HOME")) do
    display =
      case home do
        home when is_binary(home) and home != "" ->
          case Path.relative_to(path, home) do
            ^path -> path
            relative -> "~/" <> relative
          end

        _other ->
          path
      end

    components = display |> String.split("/") |> Enum.reject(&(&1 == ""))

    if length(components) > 3 do
      "…/" <> (components |> Enum.take(-2) |> Enum.join("/"))
    else
      display
    end
  end

  defp git_branch(working_dir) do
    case run("git", ["rev-parse", "--abbrev-ref", "HEAD"], working_dir) do
      {:ok, ""} -> nil
      {:ok, branch} -> branch
      :error -> nil
    end
  end

  defp gh_pull_request(working_dir, branch) do
    with {:ok, output} when output != "" <- run("gh", ["pr", "view", branch, "--json", "number"], working_dir),
         {:ok, %{"number" => number}} <- JSON.decode(output) do
      number
    else
      _other -> nil
    end
  end

  defp gh_checks(working_dir, number) do
    with {:ok, output} when output != "" <-
           run("gh", ["pr", "checks", to_string(number), "--json", "name,conclusion"], working_dir),
         {:ok, checks} when is_list(checks) <- JSON.decode(output) do
      tally(checks)
    else
      _other -> nil
    end
  end

  @doc "Counts checks into passing, failing, and pending buckets."
  def tally(checks) do
    Enum.reduce(checks, %{passing: 0, failing: 0, pending: 0}, fn check, counts ->
      case check["conclusion"] do
        "SUCCESS" ->
          %{counts | passing: counts.passing + 1}

        conclusion when conclusion in ~w(FAILURE CANCELLED TIMED_OUT ACTION_REQUIRED) ->
          %{counts | failing: counts.failing + 1}

        _other ->
          %{counts | pending: counts.pending + 1}
      end
    end)
  end

  # `gh` in particular is often not installed. Looking the executable up first
  # keeps a missing tool from raising inside the refresh task, where the crash
  # report would be written straight over the drawn frame.
  defp run(program, arguments, working_dir) do
    with executable when is_binary(executable) <- System.find_executable(program),
         {output, 0} <-
           MuonTrap.cmd(executable, arguments,
             cd: working_dir,
             timeout: @command_timeout,
             env: [{"NO_COLOR", "1"}, {"GH_NO_UPDATE_NOTIFIER", "1"}, {"GH_TOKEN", nil}]
           ) do
      {:ok, String.trim(output)}
    else
      _other -> :error
    end
  end
end
