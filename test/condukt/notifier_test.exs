defmodule Condukt.NotifierTest do
  use ExUnit.Case, async: true

  alias Condukt.Notifier
  alias Condukt.Notifiers.PubSub
  alias Condukt.Session
  alias Condukt.Sessions

  defmodule Recorder do
    @moduledoc false
    @behaviour Condukt.Notifier

    @impl true
    def publish(session_id, event, opts) do
      # Tolerates being called without options, which is what a bare module
      # spec passes.
      if to = Keyword.get(opts, :to), do: send(to, {:published, session_id, event, opts})
      :ok
    end
  end

  defmodule Agent do
    @moduledoc false
    use Condukt.Agent

    @impl Condukt
    def model, do: "openrouter:test"
  end

  describe "dispatching a spec" do
    test "no notifier is the default and does nothing" do
      assert Notifier.publish(nil, "session", {:text, "hi"}) == :ok
    end

    test "a bare module is called with empty options" do
      assert Notifier.publish(Recorder, "session", {:text, "hi"}) == :ok
    end

    test "options are handed back on every call" do
      Notifier.publish({Recorder, to: self(), topic: "runs"}, "session-1", {:text, "hi"})

      assert_receive {:published, "session-1", {:text, "hi"}, opts}
      assert opts[:topic] == "runs"
    end
  end

  describe "inside a session" do
    # Alongside the direct subscribers, not instead of them: adding a notifier
    # must not change what an existing caller receives.
    test "an event reaches both the subscriber and the notifier" do
      {:ok, session} = Sessions.start(Agent, api_key: "test", notifier: {Recorder, to: self()})
      id = Session.id(session)
      on_exit(fn -> Sessions.stop(id) end)

      reference = make_ref()
      :ok = GenServer.call(session, {:subscribe, self(), reference})
      GenServer.cast(session, {:broadcast_event, {:text, "hello"}, reference})

      assert_receive {^reference, {:text, "hello"}}
      assert_receive {:published, ^id, {:text, "hello"}, _opts}
    end

    test "a session without one publishes nothing" do
      {:ok, session} = Sessions.start(Agent, api_key: "test")
      on_exit(fn -> Sessions.stop(Session.id(session)) end)

      reference = make_ref()
      :ok = GenServer.call(session, {:subscribe, self(), reference})
      GenServer.cast(session, {:broadcast_event, {:text, "hello"}, reference})

      assert_receive {^reference, {:text, "hello"}}
      refute_receive {:published, _id, _event, _opts}
    end
  end

  describe "the PubSub adapter" do
    test "namespaces topics by session" do
      assert PubSub.topic("abc") == "condukt:session:abc"
      assert PubSub.topic("abc", "runs:") == "runs:abc"
    end
  end
end
