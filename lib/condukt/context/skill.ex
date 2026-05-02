defmodule Condukt.Context.Skill do
  @moduledoc """
  Metadata for a discovered local skill.
  """

  @enforce_keys [:name, :path]
  defstruct [:name, :path, description: nil]
end
