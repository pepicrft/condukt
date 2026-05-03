defmodule Condukt.Workflows.Error do
  @moduledoc """
  Exception raised for workflow loading and runtime errors.
  """

  defexception [:reason, message: "workflow error"]

  @impl true
  def exception(reason) do
    %__MODULE__{reason: reason, message: inspect(reason)}
  end
end
