defmodule Glossia.Agent.Tools.Bash do
  @moduledoc """
  Tool for executing bash commands.

  Runs commands in the current working directory and returns stdout/stderr.
  Output is truncated to reasonable limits.

  ## Parameters

  - `command` - The bash command to execute
  - `cwd` - Directory to run the command in (optional)
  - `packages` - Nix packages to make available for this command (optional)
  - `timeout` - Timeout in seconds (optional, default: 120)

  ## Safety

  This tool executes arbitrary shell commands. Use with caution and
  consider implementing allowlists or sandboxing for production use.
  """

  use Glossia.Agent.Tool

  @max_lines 2000
  @max_bytes 50 * 1024
  @default_timeout 120_000

  @impl true
  def name, do: "Bash"

  @impl true
  def description do
    """
    Execute a bash command in the current working directory. Returns stdout and stderr.
    Output is truncated to #{@max_lines} lines or #{div(@max_bytes, 1024)}KB.
    Optionally provide a cwd, Nix packages to install for this command, and a timeout in seconds.
    """
    |> String.trim()
  end

  @impl true
  def parameters do
    %{
      type: "object",
      properties: %{
        command: %{
          type: "string",
          description: "Bash command to execute"
        },
        cwd: %{
          type: "string",
          description: "Directory to run the command in (relative or absolute)"
        },
        packages: %{
          type: "array",
          description: "Nix packages to make available for this command. Simple names are resolved as nixpkgs#<name>."
        },
        timeout: %{
          type: "number",
          description: "Timeout in seconds (optional, default: #{div(@default_timeout, 1000)})"
        }
      },
      required: ["command"]
    }
  end

  @impl true
  def call(%{"command" => command} = args, context) do
    base_cwd = context[:cwd] || File.cwd!()
    cwd = resolve_cwd(args["cwd"], base_cwd)
    packages = List.wrap(args["packages"] || [])
    timeout = trunc((args["timeout"] || div(@default_timeout, 1000)) * 1000)
    opts = context[:opts] || []

    case execute_command(command, cwd, timeout, packages, opts) do
      {:ok, output, exit_code} ->
        {truncated_output, truncated?} = truncate_output(output)

        result =
          [
            truncated_output,
            truncated? && "(output truncated)",
            exit_code != 0 && "(exit code: #{exit_code})"
          ]
          |> Enum.reject(&(&1 in [false, nil, ""]))
          |> Enum.join("\n\n")

        {:ok, result}

      {:error, :timeout} ->
        {:error, "Command timed out after #{div(timeout, 1000)} seconds"}

      {:error, reason} ->
        {:error, "Command failed: #{inspect(reason)}"}
    end
  end

  defp resolve_cwd(nil, cwd), do: cwd

  defp resolve_cwd(path, cwd) do
    if Path.type(path) == :absolute do
      path
    else
      Path.expand(path, cwd)
    end
  end

  defp execute_command(command, cwd, timeout, packages, opts) do
    nix_executable = Keyword.get(opts, :nix_executable, "nix")
    runner = Keyword.get(opts, :runner, &run_invocation/5)

    with {:ok, {executable, args}} <- build_invocation(command, packages, nix_executable, opts) do
      runner.(executable, args, cwd, timeout, build_env())
    end
  end

  defp build_env do
    [
      {"TERM", "dumb"},
      {"PAGER", "cat"},
      {"GIT_PAGER", "cat"}
    ]
  end

  defp build_invocation(command, [], _nix_executable, _opts) do
    {:ok, {"bash", ["-c", command]}}
  end

  defp build_invocation(command, packages, nix_executable, opts) do
    if Keyword.has_key?(opts, :runner) or nix_available?(nix_executable) do
      normalized_packages = Enum.map(packages, &normalize_package/1)

      {:ok, {nix_executable, ["shell" | normalized_packages] ++ ["--command", "bash", "-c", command]}}
    else
      {:error, "Nix is required when packages are specified, but `#{nix_executable}` was not found in PATH"}
    end
  end

  defp nix_available?(nix_executable) do
    if Path.type(nix_executable) == :absolute do
      File.exists?(nix_executable)
    else
      :os.find_executable(String.to_charlist(nix_executable)) != false
    end
  end

  defp normalize_package(package) do
    package = String.trim(package)

    if String.contains?(package, "#") do
      package
    else
      "nixpkgs##{package}"
    end
  end

  defp run_invocation(executable, args, cwd, timeout, env) do
    case MuonTrap.cmd(executable, args,
           cd: cwd,
           stderr_to_stdout: true,
           env: env,
           timeout: timeout
         ) do
      {_output, :timeout} -> {:error, :timeout}
      {output, exit_code} -> {:ok, output, exit_code}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp truncate_output(output) do
    lines = String.split(output, "\n")

    {lines, truncated_by_lines?} =
      if length(lines) > @max_lines do
        {Enum.take(lines, @max_lines), true}
      else
        {lines, false}
      end

    content = Enum.join(lines, "\n")

    {content, truncated_by_bytes?} =
      if byte_size(content) > @max_bytes do
        {String.slice(content, 0, @max_bytes), true}
      else
        {content, false}
      end

    {content, truncated_by_lines? or truncated_by_bytes?}
  end
end
