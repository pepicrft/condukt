defmodule Condukt.CLI.Browser do
  @moduledoc """
  "Open this URL in the user's browser", isolated behind a function value.

  Keeping the side effect behind an injectable function keeps it out of the
  interface's state machine, so tests can record what would have been opened
  without spawning processes.
  """

  @doc """
  Opens a URL with the host's default handler.

  Failure is deliberately silent: the interface already shows the URL inline,
  and a terminal application has nothing useful to do with the error.
  """
  def open(url) do
    with {command, arguments} <- opener(),
         executable when is_binary(executable) <- System.find_executable(command) do
      MuonTrap.cmd(executable, arguments ++ [url], stderr_to_stdout: true, timeout: to_timeout(second: 10))
    end

    :ok
  end

  @doc "A no-op opener for hosts that should never launch a browser."
  def ignore(_url), do: :ok

  defp opener do
    case :os.type() do
      {:unix, :darwin} -> {"open", []}
      {:unix, _flavour} -> {"xdg-open", []}
      {:win32, _flavour} -> {"cmd", ["/c", "start", ""]}
      _other -> nil
    end
  end
end
