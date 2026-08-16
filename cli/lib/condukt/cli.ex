defmodule Condukt.CLI do
  @moduledoc """
  Entry point for the `condukt` binary.

  Inside a burrito-wrapped binary the command runs synchronously from the
  supervision tree and stops the virtual machine when it finishes: burrito boots
  the release with `:elixir.start_cli`, which halts the node as soon as the boot
  call returns, so anything asynchronous would lose the race against its own
  process exiting. Outside a wrapped binary this is inert, which keeps
  `mix test` and `iex -S mix` free of a terminal interface nobody asked for.
  Use `mix condukt` to drive it during development.
  """

  alias Burrito.Util.Args
  alias Condukt.CLI.ACP
  alias Condukt.CLI.Browser
  alias Condukt.CLI.Credentials
  alias Condukt.CLI.Headless
  alias Condukt.CLI.OAuth
  alias Condukt.CLI.OpenRouter
  alias Condukt.CLI.Options
  alias Condukt.CLI.TUI
  alias Condukt.CLI.Workspace

  @name "condukt"
  @version Mix.Project.config()[:version]

  @doc false
  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, restart: :temporary}
  end

  @doc """
  Runs the command a wrapped binary was invoked with, then stops the machine.

  Always returns `:ignore`: this is a supervision-tree entry point, not a
  process to supervise.
  """
  def start_link(opts \\ []) do
    if standalone?(), do: main(Args.argv(), opts)
    :ignore
  end

  @doc """
  Runs one invocation.

  ## Options

    * `:halt` - one-argument function called with the exit code instead of
      `System.halt/1`; exists for tests and embedders
  """
  def main(argv, opts \\ []) do
    halt = Keyword.get(opts, :halt, &System.halt/1)

    argv
    |> Options.parse()
    |> execute(opts)
    |> halt.()
  end

  defp execute({:help, text}, _opts) do
    IO.puts(text)
    0
  end

  defp execute({:error, message}, _opts), do: fail(message)

  defp execute({:ok, command, log_level}, opts) do
    configure_logging(log_level)
    run(command, opts)
  end

  @doc """
  Turns diagnostics on at the requested level.

  Off by default: this runs inside someone else's terminal, and an agent that
  volunteers its internals is noise. When they are asked for they go to standard
  error, never standard output, so a `--json` response stays parseable and the
  protocol server's frames stay well formed.
  """
  def configure_logging(:none), do: :ok

  def configure_logging(level) do
    :logger.add_handler(:condukt_cli, :logger_std_h, %{
      level: level,
      config: %{type: :standard_error},
      formatter: {:logger_formatter, %{single_line: true, legacy_header: false}}
    })

    :ok
  end

  # Loading the renderer here makes `--version` a proof of life for the bundled
  # native library. A binary whose renderer cannot load is broken for every
  # interactive run, and this is the one command that can say so without a
  # terminal, so packaging mistakes surface in continuous integration rather
  # than on a user's machine.
  defp run(:version, _opts) do
    case ExRatatui.Native.ensure_loaded() do
      :ok ->
        IO.puts("#{@name} #{@version}")
        0

      {:error, reason} ->
        fail("the terminal renderer could not be loaded: #{inspect(reason)}")
    end
  end

  defp run(:tui, opts), do: run_tui(opts)

  defp run(:acp, _opts), do: finish(ACP.run(version: @version))

  defp run({:exec, exec_opts}, _opts), do: finish(Headless.run(exec_opts))

  defp run(:import_pi_credentials, _opts) do
    case Credentials.import_pi_credential() do
      {:ok, true} -> say("Imported OpenRouter credential from Pi.")
      {:ok, false} -> say("Condukt already has an OpenRouter credential.")
      {:error, reason} -> fail(describe(reason))
    end
  end

  defp run({:connect, provider, api_key}, _opts) do
    if String.downcase(provider) == "openrouter" do
      connect(api_key)
    else
      fail("only OpenRouter is supported currently")
    end
  end

  defp run({:files, cwd}, _opts) do
    root = cwd || File.cwd!()

    case Workspace.files(root) do
      {:ok, files} ->
        Enum.each(files, &IO.puts/1)
        0

      {:error, reason} ->
        fail("could not list #{root}: #{:file.format_error(reason)}")
    end
  end

  defp run({:read, path, cwd}, _opts) do
    case Workspace.read(cwd || File.cwd!(), path) do
      {:ok, contents} ->
        IO.write(contents)
        0

      {:error, message} ->
        fail(message)
    end
  end

  defp run_tui(opts) do
    # The interface is a linked child, and it can die between `start_link`
    # returning and this process getting a chance to say how it wants to hear
    # about that. Trapping first turns the exit signal into a message either
    # way, so a terminal that cannot be initialized is reported the same way
    # whether the caller happens to trap exits already (a supervisor, inside a
    # wrapped binary) or not (`mix condukt`). Waiting selectively leaves any
    # other message in the mailbox for whoever it belongs to.
    Process.flag(:trap_exit, true)

    case TUI.start_link(Keyword.take(opts, [:cwd, :browser])) do
      {:ok, pid} ->
        receive do
          {:EXIT, ^pid, reason} -> exit_code_for(reason)
        end

      {:error, reason} ->
        fail("could not start the terminal interface: #{inspect(reason)}")
    end
  end

  defp exit_code_for(reason) when reason in [:normal, :shutdown], do: 0
  defp exit_code_for({:shutdown, _details}), do: 0

  defp exit_code_for(reason), do: fail("terminated: #{inspect(reason)}")

  defp connect(api_key) when is_binary(api_key) and api_key != "" do
    case store_key(api_key) do
      :ok -> say("OpenRouter is connected.")
      {:error, message} -> fail(message)
    end
  end

  defp connect(_api_key) do
    case OAuth.login(&Browser.open/1) do
      {:ok, key} -> connect(key)
      {:error, message} -> fail(message)
    end
  end

  defp store_key(api_key) do
    with :ok <- OpenRouter.validate(api_key) do
      save(api_key)
    end
  end

  defp save(api_key) do
    case OpenRouter.save_key(api_key) do
      :ok -> :ok
      {:error, reason} -> {:error, "Failed to save the OpenRouter key: #{describe(reason)}"}
    end
  end

  defp finish(:ok), do: 0
  defp finish({:error, message}), do: fail(describe(message))
  defp finish(_other), do: 0

  defp say(message) do
    IO.puts(message)
    0
  end

  defp fail(message) do
    IO.puts(:stderr, "#{@name}: #{message}")
    1
  end

  defp describe(reason) when is_binary(reason), do: reason
  defp describe({:pi_credential_missing, path}), do: "no Pi credential at #{path}"
  defp describe(:pi_credential_path_unknown), do: "could not determine the Pi credential path"
  defp describe(:pi_credential_unreadable), do: "the Pi credential file is not valid data"
  defp describe(:pi_openrouter_credential_missing), do: "Pi has no OpenRouter access credential"
  defp describe(:home_directory_unknown), do: "could not resolve the home directory"
  defp describe(reason) when is_atom(reason), do: :file.format_error(reason)
  defp describe(reason), do: inspect(reason)

  # The burrito wrapper sets this when it launches the payload, which its
  # maintainers document as the supported way to detect a wrapped binary.
  defp standalone?, do: System.get_env("__BURRITO") != nil
end
