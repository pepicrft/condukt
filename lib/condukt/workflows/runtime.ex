defmodule Condukt.Workflows.Runtime do
  @moduledoc """
  Caller-owned supervisor for workflow workers and triggers.
  """

  use Supervisor

  @doc false
  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts)

  @impl true
  def init(_opts), do: not_implemented!()

  defp not_implemented!, do: raise(RuntimeError, "Condukt.Workflows.Runtime is not implemented yet")
end
