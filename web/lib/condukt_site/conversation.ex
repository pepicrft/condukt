defmodule ConduktSite.Conversation do
  @moduledoc """
  Runs one visitor's agent session on the server.

  The session used to run in the visitor's browser, compiled to WebAssembly
  from a second implementation of the agent loop. It runs here now, as a
  supervised `Condukt.Session`, which is why the site depends on the library at
  all: there is one loop again.

  Only the loop moved. The tools it calls still run in the visitor's browser,
  reached back down the LiveView socket by `ConduktSite.BrowserTools`, which is
  why they arrive here as an argument rather than from the agent.

  A conversation belongs to the LiveView that started it, and is stopped when
  that process goes away, so a visitor closing the tab does not leave a session
  running.
  """

  alias ConduktSite.DemoAgent

  @doc """
  Starts a session for a visitor's OpenRouter credential and their page's tools.

  Returns `{:ok, session_id}`. The id rather than the pid, because the caller
  reaches the session through `Condukt.Sessions` and does not need to hold a
  process reference across a reconnect.

  The session's lifetime is tied to `owner` by a monitor rather than by the
  owner's own teardown. A LiveView that loses its connection is killed, which
  never reaches `terminate/2`, and a dropped connection is the ordinary way one
  of these ends: relying on the callback leaves a session per lost tab, running
  until the node restarts.
  """
  def start(api_key, tools \\ [], owner \\ self()) do
    with {:ok, session} <- Condukt.Sessions.start(DemoAgent, api_key: api_key, tools: tools) do
      id = Condukt.Session.id(session)

      {:ok, _reaper} =
        Task.Supervisor.start_child(ConduktSite.TaskSupervisor, reaper(id, session, owner))

      {:ok, id}
    end
  end

  # Watches both ends so it cannot outlive either: the owner going away stops
  # the session, and the session going away leaves nothing to stop.
  defp reaper(id, session, owner) do
    fn ->
      owner_ref = Process.monitor(owner)
      session_ref = Process.monitor(session)

      receive do
        {:DOWN, ^owner_ref, :process, _pid, _reason} -> stop(id)
        {:DOWN, ^session_ref, :process, _pid, _reason} -> :ok
      end
    end
  end

  @doc "Stops a conversation. Safe to call for one that has already gone."
  def stop(nil), do: :ok
  def stop(session_id), do: Condukt.Sessions.stop(session_id)

  @doc """
  Submits a prompt, streaming events back to `subscriber`.

  Events arrive as `{:agent, event}` and the turn ends with `{:agent, :done}`.
  The work runs in a task so the caller, which is a LiveView process, stays
  free to render what arrives.
  """
  def submit(session_id, prompt, subscriber) do
    case Condukt.Sessions.whereis(session_id) do
      nil ->
        {:error, :no_session}

      session ->
        Task.Supervisor.start_child(ConduktSite.TaskSupervisor, fn ->
          session
          |> Condukt.Session.stream(prompt)
          |> Enum.each(&send(subscriber, {:agent, &1}))

          send(subscriber, {:agent, :done})
        end)

        :ok
    end
  end
end
