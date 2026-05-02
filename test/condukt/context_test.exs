defmodule Condukt.ContextTest do
  use ExUnit.Case, async: true

  alias Condukt.Context

  test "discovers agents instructions and local skills from a workspace root" do
    workspace_root = tmp_dir!("workspace-context")

    File.write!(Path.join(workspace_root, "AGENTS.md"), "Follow the workspace instructions.")
    File.write!(Path.join(workspace_root, "CLAUDE.md"), "Prefer concise responses.")

    skill_dir = Path.join(workspace_root, ".agents/skills/review")
    File.mkdir_p!(skill_dir)

    File.write!(
      Path.join(skill_dir, "SKILL.md"),
      """
      ---
      name: review
      description: Review a change for risks and regressions.
      ---

      Inspect the diff and call out the highest-risk issues first.
      """
    )

    context = Context.discover(workspace_root)

    assert context.agents_md =~ "Follow the workspace instructions."
    assert context.agents_md =~ "Prefer concise responses."

    assert context.skills == [
             %Context.Skill{
               name: "review",
               path: ".agents/skills/review/SKILL.md",
               description: "Review a change for risks and regressions."
             }
           ]

    assert context.prompt =~ "## Workspace Instructions"
    assert context.prompt =~ "## Available Skills"
    assert context.prompt =~ "read `.agents/skills/review/SKILL.md` before using it"
  end

  test "deduplicates AGENTS.md and a symlinked CLAUDE.md" do
    workspace_root = tmp_dir!("workspace-context-symlink")

    File.write!(Path.join(workspace_root, "AGENTS.md"), "Follow the workspace instructions.")
    assert :ok = File.ln_s("AGENTS.md", Path.join(workspace_root, "CLAUDE.md"))

    context = Context.discover(workspace_root)

    assert context.agents_md == "Follow the workspace instructions."
  end

  test "composes base and discovered prompts" do
    composed =
      Context.compose_system_prompt(
        "You are a helpful assistant.",
        "## Workspace Instructions\n\nUse mix test."
      )

    assert composed ==
             "You are a helpful assistant.\n\n## Workspace Instructions\n\nUse mix test."
  end

  defp tmp_dir!(prefix) do
    path =
      Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive, :monotonic])}")

    File.rm_rf!(path)
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end
end
