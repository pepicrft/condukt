defmodule Mix.Tasks.Condukt.Workflows.Serve do
  @shortdoc "Serves Condukt workflows"

  @moduledoc """
  Starts a Condukt workflow runtime and blocks.
  """

  use Mix.Task

  alias Condukt.Workflows
  alias Mix.Tasks.Condukt.Workflows.Helpers

  @requirements ["app.start"]
  @impl Mix.Task
  def run(args) do
    {opts, rest} = Helpers.parse!(args, root: :string, workflows: :string, port: :integer)
    rest == [] || Mix.raise("Unexpected arguments: #{Enum.join(rest, " ")}")

    root = root_from_opts(opts)
    project = Helpers.load_project!(root)
    port = Keyword.get(opts, :port, 4000)

    case Workflows.serve(project, port: port) do
      {:ok, _pid} ->
        Mix.shell().info("Serving #{map_size(project.workflows)} workflow(s) on port #{port}")
        Process.sleep(:infinity)

      {:error, reason} ->
        Mix.raise("Could not serve workflows: #{inspect(reason)}")
    end
  end

  defp root_from_opts(opts) do
    cond do
      opts[:root] ->
        Helpers.root(opts)

      opts[:workflows] ->
        workflows_root(opts[:workflows])

      true ->
        File.cwd!()
    end
  end

  defp workflows_root(path) do
    path = Path.expand(path)

    if Path.basename(path) == "workflows" do
      Path.dirname(path)
    else
      path
    end
  end
end
