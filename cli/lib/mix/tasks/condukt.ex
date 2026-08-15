defmodule Mix.Tasks.Condukt do
  @shortdoc "Runs the terminal agent from the checkout"

  @moduledoc """
  Runs the `condukt` command without building a binary.

  Inside a wrapped binary the command is driven from the supervision tree; this
  task is the development equivalent, so a change can be tried without a release
  build.

      mix condukt
      mix condukt exec "summarize this project"
      mix condukt files

  The terminal interface needs a real terminal, so run it from a shell rather
  than piping its input or output.
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    Condukt.CLI.main(argv, halt: &exit_with/1)
  end

  # Mix owns the exit code, so a halt here would cut the task short before Mix
  # can flush its own output.
  defp exit_with(0), do: :ok
  defp exit_with(code), do: exit({:shutdown, code})
end
