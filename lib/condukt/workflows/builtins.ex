defmodule Condukt.Workflows.Builtins do
  @moduledoc false
  # Dispatches suspending builtin requests issued by the Starlark workflow
  # runtime. Each `handle/2` clause matches a request map shape and returns
  # the response value that will be marshaled back into the Starlark VM.

  @spec handle(map(), keyword()) :: map()
  def handle(%{"kind" => "run_cmd"} = request, opts) do
    handle_run_cmd(request, opts)
  end

  def handle(%{"kind" => kind}, _opts) do
    %{"ok" => false, "error" => "unsupported builtin: #{kind}", "exit_code" => 1, "stdout" => ""}
  end

  defp handle_run_cmd(%{"argv" => [program | args]} = request, opts)
       when is_binary(program) do
    args = Enum.map(args, &to_string/1)
    cwd = Map.get(request, "cwd") || Keyword.get(opts, :cwd, File.cwd!())
    env = normalize_env(Map.get(request, "env"))

    muontrap_opts =
      [cd: cwd, stderr_to_stdout: true]
      |> append_if(env != [], {:env, env})

    case safe_cmd(program, args, muontrap_opts) do
      {:ok, output, exit_code} ->
        %{
          "ok" => exit_code == 0,
          "stdout" => output,
          "exit_code" => exit_code
        }

      {:error, reason} ->
        %{
          "ok" => false,
          "error" => "command failed: #{inspect(reason)}",
          "stdout" => "",
          "exit_code" => 1
        }
    end
  end

  defp handle_run_cmd(_request, _opts) do
    %{
      "ok" => false,
      "error" => "run_cmd requires a non-empty argv list",
      "stdout" => "",
      "exit_code" => 1
    }
  end

  defp safe_cmd(program, args, opts) do
    case System.find_executable(program) do
      nil ->
        {:error, {:not_found, program}}

      _ ->
        {output, status} = MuonTrap.cmd(program, args, opts)
        {:ok, output, status}
    end
  rescue
    error -> {:error, error}
  end

  defp normalize_env(nil), do: []

  defp normalize_env(map) when is_map(map) do
    Enum.map(map, fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp normalize_env(_), do: []

  defp append_if(opts, false, _entry), do: opts
  defp append_if(opts, true, entry), do: opts ++ [entry]
end
