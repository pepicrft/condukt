defmodule Condukt.SessionTest do
  use ExUnit.Case, async: true

  alias Condukt.Message
  alias Condukt.SessionStore.Snapshot

  defmodule ConfigAgent do
    use Condukt

    @impl true
    def system_prompt, do: "module prompt"

    @impl true
    def init(_opts) do
      {:ok, :ok}
    end
  end

  defmodule RecordingStore do
    @behaviour Condukt.SessionStore

    @impl true
    def load(opts) do
      case Keyword.get(opts, :snapshot) do
        nil -> :not_found
        snapshot -> {:ok, snapshot}
      end
    end

    @impl true
    def save(snapshot, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:saved_snapshot, snapshot})
      :ok
    end

    @impl true
    def clear(opts) do
      send(Keyword.fetch!(opts, :test_pid), :cleared_snapshot)
      :ok
    end
  end

  test "uses config defaults when options are omitted" do
    {:ok, pid} =
      ConfigAgent.start_link(
        config: [
          api_key: "config-key",
          model: "openai:gpt-4o-mini",
          system_prompt: "config prompt",
          thinking_level: :low,
          cwd: "/tmp/agent"
        ],
        discover_workspace_context: false
      )

    state = :sys.get_state(pid)

    assert state.api_key == "config-key"
    assert state.model == "openai:gpt-4o-mini"
    assert state.system_prompt == "config prompt"
    assert state.thinking_level == :low
    assert state.cwd == "/tmp/agent"
    assert state.user_state == :ok

    GenServer.stop(pid)
  end

  test "start_link options override config values" do
    {:ok, pid} =
      ConfigAgent.start_link(
        config: [
          api_key: "config-key",
          system_prompt: "config prompt"
        ],
        api_key: "option-key",
        system_prompt: "option prompt",
        discover_workspace_context: false
      )

    state = :sys.get_state(pid)

    assert state.api_key == "option-key"
    assert state.system_prompt == "option prompt"
    assert state.user_state == :ok

    GenServer.stop(pid)
  end

  test "restores persisted session messages and settings when not explicitly configured" do
    snapshot = %Snapshot{
      messages: [Message.user("restored prompt"), Message.assistant("restored reply")],
      model: "openai:gpt-4o-mini",
      thinking_level: :low,
      system_prompt: "persisted prompt"
    }

    {:ok, pid} =
      ConfigAgent.start_link(
        session_store: {RecordingStore, snapshot: snapshot, test_pid: self()},
        discover_workspace_context: false
      )

    state = :sys.get_state(pid)

    assert state.messages == snapshot.messages
    assert state.model == snapshot.model
    assert state.thinking_level == snapshot.thinking_level
    assert state.system_prompt == snapshot.system_prompt

    GenServer.stop(pid)
  end

  test "explicit options override restored session settings" do
    snapshot = %Snapshot{
      messages: [Message.user("restored prompt")],
      model: "openai:gpt-4o-mini",
      thinking_level: :low,
      system_prompt: "persisted prompt"
    }

    {:ok, pid} =
      ConfigAgent.start_link(
        model: "anthropic:claude-sonnet-4-20250514",
        thinking_level: :high,
        system_prompt: "explicit prompt",
        session_store: {RecordingStore, snapshot: snapshot, test_pid: self()},
        discover_workspace_context: false
      )

    state = :sys.get_state(pid)

    assert state.messages == snapshot.messages
    assert state.model == "anthropic:claude-sonnet-4-20250514"
    assert state.thinking_level == :high
    assert state.system_prompt == "explicit prompt"

    GenServer.stop(pid)
  end

  test "clear removes persisted session state" do
    snapshot = %Snapshot{
      messages: [Message.user("restored prompt")],
      model: "openai:gpt-4o-mini",
      thinking_level: :low,
      system_prompt: "persisted prompt"
    }

    {:ok, pid} =
      ConfigAgent.start_link(
        session_store: {RecordingStore, snapshot: snapshot, test_pid: self()},
        discover_workspace_context: false
      )

    assert :ok = Condukt.clear(pid)
    assert_receive :cleared_snapshot
    assert Condukt.history(pid) == []

    GenServer.stop(pid)
  end

  test "stream completion updates history and persists the final snapshot" do
    ref = make_ref()
    messages = [Message.user("hello"), Message.assistant("world")]

    state = %Condukt.Session{
      agent_module: ConfigAgent,
      model: "openai:gpt-4o-mini",
      thinking_level: :medium,
      configured_system_prompt: "prompt",
      system_prompt: "prompt\n\n## Workspace Instructions\n\nUse mix test.",
      cwd: "/tmp/agent",
      session_store: {RecordingStore, test_pid: self()},
      workspace_context: %{agents_md: nil, skills: [], prompt: nil},
      user_state: :ok
    }

    assert {:noreply, updated_state} =
             Condukt.Session.handle_cast(
               {:stream_complete, ref, {:ok, messages, "world"}},
               state
             )

    assert updated_state.messages == messages

    assert_receive {:saved_snapshot,
                    %Snapshot{
                      messages: ^messages,
                      model: "openai:gpt-4o-mini",
                      thinking_level: :medium,
                      system_prompt: "prompt"
                    }}
  end

  test "discovers workspace instructions and local skills from cwd" do
    cwd = tmp_dir!("session-context")

    File.write!(Path.join(cwd, "AGENTS.md"), "Always run project checks.")

    skill_dir = Path.join(cwd, ".agents/skills/release")
    File.mkdir_p!(skill_dir)

    File.write!(
      Path.join(skill_dir, "SKILL.md"),
      """
      ---
      description: Prepare a release safely.
      ---

      Verify the changelog and version before releasing.
      """
    )

    {:ok, pid} =
      ConfigAgent.start_link(
        cwd: cwd,
        system_prompt: "base prompt"
      )

    state = :sys.get_state(pid)

    assert state.configured_system_prompt == "base prompt"
    assert state.system_prompt =~ "base prompt"
    assert state.system_prompt =~ "Always run project checks."
    assert state.system_prompt =~ ".agents/skills/release/SKILL.md"

    assert state.workspace_context.skills == [
             %Condukt.Context.Skill{
               name: "release",
               path: ".agents/skills/release/SKILL.md",
               description: "Prepare a release safely."
             }
           ]

    GenServer.stop(pid)
  end

  test "workspace discovery can be disabled" do
    cwd = tmp_dir!("session-context-disabled")
    File.write!(Path.join(cwd, "AGENTS.md"), "Do not leak into the prompt.")

    {:ok, pid} =
      ConfigAgent.start_link(
        cwd: cwd,
        system_prompt: "base prompt",
        discover_workspace_context: false
      )

    state = :sys.get_state(pid)

    assert state.system_prompt == "base prompt"
    assert state.workspace_context == %{agents_md: nil, skills: [], prompt: nil}

    GenServer.stop(pid)
  end

  defp tmp_dir!(prefix) do
    path =
      Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive, :monotonic])}")

    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end
end
