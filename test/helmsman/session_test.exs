defmodule Helmsman.SessionTest do
  use ExUnit.Case, async: true

  alias Helmsman.Message
  alias Helmsman.SessionStore.Snapshot

  defmodule RecordingRuntimeProvider do
    @behaviour Helmsman.RuntimeProvider

    @impl true
    def init(opts) do
      send(Keyword.fetch!(opts, :test_pid), {:runtime_provider_init, opts})
      {:ok, %{provider: :recording, cwd: Keyword.fetch!(opts, :cwd)}}
    end

    @impl true
    def terminate(_session), do: :ok
  end

  defmodule ConfigAgent do
    use Helmsman

    @impl true
    def system_prompt, do: "module prompt"

    @impl true
    def init(_opts) do
      {:ok, :ok}
    end
  end

  defmodule RecordingStore do
    @behaviour Helmsman.SessionStore

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
        ]
      )

    state = :sys.get_state(pid)

    assert state.api_key == "config-key"
    assert state.model == "openai:gpt-4o-mini"
    assert state.system_prompt == "config prompt"
    assert state.thinking_level == :low
    assert state.cwd == "/tmp/agent"
    assert state.runtime_provider == Helmsman.RuntimeProvider.Local
    assert state.runtime_provider_session == %{cwd: "/tmp/agent"}
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
        system_prompt: "option prompt"
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
      ConfigAgent.start_link(session_store: {RecordingStore, snapshot: snapshot, test_pid: self()})

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
        session_store: {RecordingStore, snapshot: snapshot, test_pid: self()}
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
      ConfigAgent.start_link(session_store: {RecordingStore, snapshot: snapshot, test_pid: self()})

    assert :ok = Helmsman.clear(pid)
    assert_receive :cleared_snapshot
    assert Helmsman.history(pid) == []

    GenServer.stop(pid)
  end

  test "stream completion updates history and persists the final snapshot" do
    ref = make_ref()
    messages = [Message.user("hello"), Message.assistant("world")]

    state = %Helmsman.Session{
      agent_module: ConfigAgent,
      model: "openai:gpt-4o-mini",
      thinking_level: :medium,
      system_prompt: "prompt",
      cwd: "/tmp/agent",
      session_store: {RecordingStore, test_pid: self()},
      user_state: :ok
    }

    assert {:noreply, updated_state} =
             Helmsman.Session.handle_cast(
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

  test "initializes the configured runtime provider" do
    {:ok, pid} =
      ConfigAgent.start_link(
        cwd: "/tmp/agent",
        runtime_provider: {RecordingRuntimeProvider, test_pid: self()}
      )

    assert_receive {:runtime_provider_init, opts}
    assert opts[:agent_module] == ConfigAgent
    assert opts[:cwd] == "/tmp/agent"
    assert opts[:test_pid] == self()

    state = :sys.get_state(pid)

    assert state.runtime_provider == {RecordingRuntimeProvider, test_pid: self()}
    assert state.runtime_provider_session == %{provider: :recording, cwd: "/tmp/agent"}

    GenServer.stop(pid)
  end
end
