defmodule Condukt.CLI.Command do
  @moduledoc """
  Runs the host tools the interface needs, capturing everything they write.

  Capturing is the point of this module, not an implementation detail. A child
  process inherits the virtual machine's standard error unless it is redirected,
  and that is the terminal the interface is drawing on: one line written there
  scrolls the screen out from under the renderer, and because the renderer
  repaints by diffing cells, every later redraw lands a row off. Nothing run
  through here may reach the terminal.

  Looking the executable up first keeps a missing tool from raising inside the
  task that called it, where the crash report would be written over the frame
  for the same reason.
  """

  @default_timeout to_timeout(second: 4)

  @doc """
  Runs a command and returns its trimmed output.

  Returns `{:ok, output}` when the command is found and exits successfully, and
  `:error` for anything else: a missing executable, a non-zero exit, or a
  timeout. Callers treat all three the same way, because each one means "this is
  not available right now" rather than something worth interrupting the user
  over.

  ## Options

    * `:cd` - working directory
    * `:timeout` - milliseconds before the command is stopped
    * `:env` - extra environment as `{name, value}` pairs; a `nil` value removes
      the variable
  """
  def run(program, arguments, opts \\ []) do
    with executable when is_binary(executable) <- System.find_executable(program),
         {output, 0} <- capture(executable, arguments, opts) do
      {:ok, String.trim(output)}
    else
      _other -> :error
    end
  end

  @doc """
  Runs a command and returns its output as raw bytes.

  Same contract as `run/3`. Image data is not text and must not be trimmed or
  validated as a string on the way through.
  """
  def run_binary(program, arguments, opts \\ []) do
    with executable when is_binary(executable) <- System.find_executable(program),
         {output, 0} <- capture(executable, arguments, opts) do
      {:ok, output}
    else
      _other -> :error
    end
  end

  defp capture(executable, arguments, opts) do
    MuonTrap.cmd(
      executable,
      arguments,
      [stderr_to_stdout: true, timeout: Keyword.get(opts, :timeout, @default_timeout)] ++
        Keyword.take(opts, [:cd, :env])
    )
  end
end
