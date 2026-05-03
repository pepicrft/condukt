defmodule Condukt.Workflows.Runtime.Worker do
  @moduledoc """
  Runtime worker responsible for invoking one materialized workflow.
  """

  use GenServer

  @doc false
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc false
  def invoke(_name, _input), do: not_implemented!()

  @impl true
  def init(_opts), do: not_implemented!()

  defp not_implemented!, do: raise(RuntimeError, "Condukt.Workflows.Runtime.Worker is not implemented yet")
end
