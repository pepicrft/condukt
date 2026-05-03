defmodule Condukt.Workflows.Workflow do
  @moduledoc """
  Materialized workflow declaration.

  The struct stores only Elixir data, never pointers into the Starlark runtime.
  """

  @type t :: %__MODULE__{
          name: String.t(),
          source_path: Path.t(),
          agent: map() | nil,
          tools: [term()],
          sandbox: term(),
          triggers: [map()],
          inputs_schema: map() | nil,
          system_prompt: String.t() | nil,
          model: String.t() | nil
        }

  defstruct [
    :name,
    :source_path,
    :agent,
    :sandbox,
    :inputs_schema,
    :system_prompt,
    :model,
    tools: [],
    triggers: []
  ]
end
