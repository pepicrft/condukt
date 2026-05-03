defmodule Mix.Tasks.Condukt.Workflows.Run do
  @shortdoc "Runs a Condukt workflow"

  @moduledoc """
  Runs one Condukt workflow from a project.
  """

  use Mix.Task

  alias Condukt.Workflows
  alias Mix.Tasks.Condukt.Workflows.Helpers

  @requirements ["app.start"]
  @impl Mix.Task
  def run(args) do
    {opts, rest} = Helpers.parse!(args, root: :string, input: :string)

    name =
      case rest do
        [name] -> name
        [] -> Mix.raise("Expected workflow name")
        _ -> Mix.raise("Expected exactly one workflow name")
      end

    project =
      opts
      |> Helpers.root()
      |> Helpers.load_project!()

    input = Helpers.decode_input!(opts[:input])

    case Workflows.run(project, name, input) do
      {:ok, result} -> Mix.shell().info(Helpers.format_result(result))
      {:error, reason} -> Mix.raise("Workflow run failed: #{inspect(reason)}")
    end
  end
end
