defmodule Condukt.CLI.Application do
  @moduledoc """
  Supervision tree for the terminal agent.

  `Condukt.CLI` is started last and, inside a wrapped binary, blocks here for
  the whole run: burrito boots the release with `:elixir.start_cli`, which halts
  the node as soon as the boot call returns, so the command has to hold
  application startup open until it is finished.
  """

  use Application

  @impl Application
  def start(_type, _args) do
    children = [
      {DynamicSupervisor, name: Condukt.CLI.SessionSupervisor, strategy: :one_for_one},
      {Task.Supervisor, name: Condukt.CLI.TaskSupervisor},
      Condukt.CLI
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Condukt.CLI.Supervisor)
  end
end
