defmodule Condukt.CLI.Session do
  @moduledoc """
  Starts and drives the agent session behind every Condukt host.

  Sessions run under a dynamic supervisor rather than linked to the interface,
  so a failed turn never takes the terminal down with it, and streaming is
  forwarded to a caller's mailbox so the frame loop stays free.
  """

  alias Condukt.CLI.Agent

  @doc """
  Starts a session for an OpenRouter key.

  ## Options

    * `:cwd` - workspace root for the agent's tools (default: the current directory)
    * `:supervisor` - dynamic supervisor to start under (default: the CLI's)
  """
  def start(api_key, opts \\ []) do
    cwd = Keyword.get_lazy(opts, :cwd, &File.cwd!/0)
    supervisor = Keyword.get(opts, :supervisor, Condukt.CLI.SessionSupervisor)

    child =
      Supervisor.child_spec({Agent, [api_key: api_key, cwd: cwd, load_project_instructions: true]},
        restart: :temporary
      )

    DynamicSupervisor.start_child(supervisor, child)
  end

  @doc """
  Streams a prompt, forwarding every event to `subscriber`.

  The subscriber receives `{:agent_event, event}` for each event the session
  emits and `{:agent_done, :ok}` once the turn is over. Returns the task so the
  caller can stop a turn it no longer wants.
  """
  def stream_to(session, prompt, subscriber, opts \\ []) do
    {supervisor, prompt_opts} = Keyword.pop(opts, :supervisor, Condukt.CLI.TaskSupervisor)

    Task.Supervisor.start_child(supervisor, fn ->
      session
      |> Condukt.Session.stream(prompt, prompt_opts)
      |> Enum.each(fn event -> send(subscriber, {:agent_event, event}) end)

      send(subscriber, {:agent_done, :ok})
    end)
  end
end
