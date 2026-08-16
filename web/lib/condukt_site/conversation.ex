defmodule ConduktSite.Conversation do
  @moduledoc """
  Runs one visitor's agent session on the server.

  The session used to run in the visitor's browser, compiled to WebAssembly
  from a second implementation of the agent loop. It runs here now, as a
  supervised `Condukt.Session`, which is why the site depends on the library at
  all: there is one loop again.

  A conversation belongs to the LiveView that started it. It is stopped when
  that process goes away, so a visitor closing the tab does not leave a session
  running.
  """

  alias ConduktSite.DemoAgent

  @doc """
  Starts a session for a visitor's OpenRouter credential.

  Returns `{:ok, session_id}`. The id rather than the pid, because the caller
  reaches the session through `Condukt.Sessions` and does not need to hold a
  process reference across a reconnect.
  """
  def start(api_key) do
    with {:ok, session} <- Condukt.Sessions.start(DemoAgent, api_key: api_key) do
      {:ok, Condukt.Session.id(session)}
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
