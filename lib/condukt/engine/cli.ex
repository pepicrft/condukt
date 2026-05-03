defmodule Condukt.Engine.CLI do
  @moduledoc """
  Command-line entrypoint for the standalone Condukt engine.

  The engine exposes workflow project commands without requiring Elixir or Mix
  on the target machine.
  """

  alias Condukt.Workflows
  alias Condukt.Workflows.{Lockfile, NIF, Resolver, Workflow}

  @doc """
  Runs the engine command line and returns the process exit status.
  """
  def main(args) when is_list(args) do
    args
    |> dispatch()
    |> print_result()
  end

  defp dispatch([]), do: {:ok, usage()}
  defp dispatch(["help"]), do: {:ok, usage()}
  defp dispatch(["--help"]), do: {:ok, usage()}
  defp dispatch(["-h"]), do: {:ok, usage()}
  defp dispatch(["version"]), do: {:ok, version()}
  defp dispatch(["--version"]), do: {:ok, version()}
  defp dispatch(["workflows", "check" | args]), do: check(args)
  defp dispatch(["workflows.check" | args]), do: check(args)
  defp dispatch(["workflows", "lock" | args]), do: lock(args)
  defp dispatch(["workflows.lock" | args]), do: lock(args)
  defp dispatch(["workflows", "run" | args]), do: run_workflow(args)
  defp dispatch(["workflows.run" | args]), do: run_workflow(args)
  defp dispatch(["workflows", "serve" | args]), do: serve(args)
  defp dispatch(["workflows.serve" | args]), do: serve(args)
  defp dispatch([unknown | _args]), do: {:error, "Unknown command: #{unknown}\n\n#{usage()}"}

  defp check(args) do
    with {:ok, opts, []} <- parse_options(args, root: :string),
         {:ok, project} <- load_project(root(opts)) do
      case validate_project(project) do
        [] ->
          {:ok, "Validated #{map_size(project.workflows)} workflow(s)"}

        errors ->
          {:error, Enum.map_join(errors, "\n", &format_validation_error/1)}
      end
    else
      {:ok, _opts, rest} -> {:error, "Unexpected arguments: #{Enum.join(rest, " ")}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp lock(args) do
    with {:ok, opts, []} <- parse_options(args, root: :string, upgrade: :boolean, offline: :boolean),
         root = root(opts),
         {:ok, lockfile} <- load_lockfile(root),
         {:ok, requirements} <- collect_requirements(root),
         {:ok, lockfile} <- resolve(requirements, opts, lockfile),
         path = Path.join(root, "condukt.lock"),
         :ok <- write_lockfile(lockfile, path) do
      {:ok, "Wrote #{path}"}
    else
      {:ok, _opts, rest} -> {:error, "Unexpected arguments: #{Enum.join(rest, " ")}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp run_workflow(args) do
    with {:ok, opts, [name]} <- parse_options(args, root: :string, input: :string),
         {:ok, input} <- decode_input(opts[:input]),
         {:ok, project} <- load_project(root(opts)),
         {:ok, result} <- Workflows.run(project, name, input) do
      {:ok, format_result(result)}
    else
      {:ok, _opts, []} -> {:error, "Expected workflow name"}
      {:ok, _opts, rest} -> {:error, "Expected exactly one workflow name, got: #{Enum.join(rest, " ")}"}
      {:error, reason} -> {:error, "Workflow run failed: #{inspect(reason)}"}
    end
  end

  defp serve(args) do
    with {:ok, opts, []} <- parse_options(args, root: :string, workflows: :string, port: :integer),
         root = root_from_serve_opts(opts),
         {:ok, project} <- load_project(root),
         port = Keyword.get(opts, :port, 4000),
         {:ok, _pid} <- Workflows.serve(project, port: port) do
      IO.puts("Serving #{map_size(project.workflows)} workflow(s) on port #{port}")
      Process.sleep(:infinity)
      {:ok, ""}
    else
      {:ok, _opts, rest} -> {:error, "Unexpected arguments: #{Enum.join(rest, " ")}"}
      {:error, reason} -> {:error, "Could not serve workflows: #{inspect(reason)}"}
    end
  end

  defp parse_options(args, switches) do
    case OptionParser.parse(args, strict: switches) do
      {opts, rest, []} -> {:ok, opts, rest}
      {_opts, _rest, invalid} -> {:error, "Invalid options: #{inspect(invalid)}"}
    end
  end

  defp root(opts) do
    opts
    |> Keyword.get(:root, File.cwd!())
    |> Path.expand()
  end

  defp root_from_serve_opts(opts) do
    cond do
      opts[:root] ->
        root(opts)

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

  defp load_project(root) do
    case Workflows.load_project(root) do
      {:ok, project} -> {:ok, project}
      {:error, reason} -> {:error, {:load_project, reason}}
    end
  end

  defp load_lockfile(root) do
    case Lockfile.load(Path.join(root, "condukt.lock")) do
      {:ok, lockfile} -> {:ok, lockfile}
      :missing -> {:ok, %Lockfile{}}
      {:error, reason} -> {:error, {:load_lockfile, reason}}
    end
  end

  defp collect_requirements(root) do
    root
    |> workflow_sources()
    |> Enum.reduce_while({:ok, []}, fn path, {:ok, acc} ->
      with {:ok, source} <- File.read(path),
           {:ok, %{"loads" => loads}} <- NIF.parse_only(source, path) do
        {:cont, {:ok, [loads | acc]}}
      else
        {:error, reason} -> {:halt, {:error, {:parse_workflow, path, reason}}}
      end
    end)
    |> case do
      {:ok, loads} -> {:ok, loads |> Enum.reverse() |> List.flatten() |> Resolver.collect_requirements()}
      {:error, reason} -> {:error, reason}
    end
  end

  defp workflow_sources(root) do
    ["workflows/**/*.star", "lib/**/*.star"]
    |> Enum.flat_map(fn pattern -> Path.wildcard(Path.join(root, pattern), match_dot: false) end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp resolve([], _opts, _lockfile), do: {:ok, %Lockfile{}}

  defp resolve(requirements, opts, lockfile) do
    requirements
    |> Resolver.resolve(
      lockfile: lockfile,
      offline: Keyword.get(opts, :offline, false),
      upgrade: Keyword.get(opts, :upgrade, false)
    )
    |> normalize_lockfile()
  end

  defp normalize_lockfile({:ok, %Lockfile{} = lockfile}), do: {:ok, lockfile}
  defp normalize_lockfile({:ok, packages}) when is_map(packages), do: {:ok, %Lockfile{packages: packages}}
  defp normalize_lockfile({:error, reason}), do: {:error, {:resolve, reason}}

  defp write_lockfile(lockfile, path) do
    case Lockfile.write(lockfile, path) do
      :ok -> :ok
      {:error, reason} -> {:error, {:write_lockfile, reason}}
    end
  end

  defp decode_input(nil), do: {:ok, %{}}

  defp decode_input(encoded) do
    case JSON.decode(encoded) do
      {:ok, input} when is_map(input) -> {:ok, input}
      {:ok, _other} -> {:error, "--input must decode to a JSON object"}
      {:error, reason} -> {:error, {:invalid_input_json, reason}}
    end
  end

  defp format_result(result) when is_binary(result), do: result
  defp format_result(result), do: JSON.encode!(result)

  defp validate_project(project) do
    project
    |> Workflows.list()
    |> Enum.flat_map(fn workflow ->
      validate_model(workflow) ++ validate_session_opts(workflow)
    end)
  end

  defp validate_model(%{model: nil}), do: []

  defp validate_model(%{model: model} = workflow) when is_binary(model) do
    case parse_model(model) do
      :ok -> []
      {:error, reason} -> [{workflow, :invalid_model, "#{model}: #{inspect(reason)}"}]
    end
  end

  defp validate_model(%{model: model} = workflow), do: [{workflow, :invalid_model, inspect(model)}]

  defp validate_session_opts(workflow) do
    case Workflow.to_session_opts(workflow) do
      {:ok, _opts} -> []
      {:error, reason} -> [{workflow, :invalid_workflow, inspect(reason)}]
    end
  end

  defp parse_model(model) do
    req_llm_model = Module.concat(ReqLLM, Model)

    cond do
      Code.ensure_loaded?(req_llm_model) and function_exported?(req_llm_model, :parse, 1) ->
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        apply(req_llm_model, :parse, [model]) |> normalize_parse_result()

      Code.ensure_loaded?(LLMDB) and function_exported?(LLMDB, :parse, 1) ->
        LLMDB.parse(model) |> normalize_parse_result()

      true ->
        ReqLLM.model(model) |> normalize_parse_result()
    end
  end

  defp normalize_parse_result({:ok, _value}), do: :ok
  defp normalize_parse_result({:error, reason}), do: {:error, reason}
  defp normalize_parse_result(other), do: {:error, other}

  defp format_validation_error({workflow, kind, message}) do
    "#{workflow.source_path}:1:1: #{kind}: #{message}"
  end

  defp print_result({:ok, ""}), do: 0

  defp print_result({:ok, output}) do
    IO.puts(output)
    0
  end

  defp print_result({:error, message}) do
    IO.puts(:stderr, message)
    1
  end

  defp version do
    :condukt
    |> Application.spec(:vsn)
    |> to_string()
  end

  defp usage do
    """
    Condukt engine #{version()}

    Usage:
      condukt version
      condukt workflows check [--root PATH]
      condukt workflows lock [--root PATH] [--offline] [--upgrade]
      condukt workflows run NAME [--root PATH] [--input JSON]
      condukt workflows serve [--root PATH] [--workflows PATH] [--port PORT]
    """
    |> String.trim()
  end
end
