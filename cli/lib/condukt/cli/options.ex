defmodule Condukt.CLI.Options do
  @moduledoc """
  Command-line parsing.

  Parsing is separated from execution so the whole surface can be exercised
  without running a command: `parse/1` returns a command description, never a
  side effect.
  """

  @switches [
    prompt: :string,
    api_key: :string,
    cwd: :string,
    image: [:string, :keep],
    verbose: :boolean,
    json: :boolean,
    color: :string,
    help: :boolean,
    version: :boolean
  ]

  @aliases [p: :prompt, v: :verbose, h: :help, i: :image]

  @colors ~w(auto always never)

  @doc """
  Parses `argv` into a command.

  Returns `{:ok, command}`, `{:error, message}`, or `{:help, text}`.
  """
  def parse(argv) do
    case OptionParser.parse(argv, strict: @switches, aliases: @aliases) do
      {_options, _rest, [{switch, _value} | _more]} -> {:error, "unknown option: #{switch}"}
      {options, rest, []} -> build(options, rest)
    end
  end

  defp build(options, rest) do
    cond do
      options[:help] -> {:help, help_text()}
      options[:version] -> {:ok, :version}
      rest == [] -> default_command(options)
      true -> subcommand(hd(rest), tl(rest), options)
    end
  end

  # `condukt -p "..."` is the same as `condukt exec "..."`; a bare `condukt`
  # starts the terminal interface.
  defp default_command(options) do
    if options[:prompt], do: exec(options[:prompt], options), else: {:ok, :tui}
  end

  defp subcommand("exec", arguments, options) do
    exec(List.first(arguments) || options[:prompt], options)
  end

  defp subcommand("acp", _arguments, _options), do: {:ok, :acp}

  defp subcommand("import-pi-credentials", _arguments, _options), do: {:ok, :import_pi_credentials}

  defp subcommand("connect", [provider | _rest], options) do
    {:ok, {:connect, provider, options[:api_key]}}
  end

  defp subcommand("connect", [], _options), do: {:error, "connect requires a provider, for example: connect openrouter"}

  defp subcommand("files", _arguments, options), do: {:ok, {:files, options[:cwd]}}

  defp subcommand("read", [path | _rest], options), do: {:ok, {:read, path, options[:cwd]}}

  defp subcommand("read", [], _options), do: {:error, "read requires a path"}

  defp subcommand("help", _arguments, _options), do: {:help, help_text()}

  defp subcommand(command, _arguments, _options), do: {:error, "unknown command: #{command}"}

  defp exec(prompt, options) do
    with {:ok, color} <- color(options[:color]) do
      {:ok,
       {:exec,
        [
          prompt: prompt,
          api_key: options[:api_key],
          cwd: options[:cwd],
          images: Keyword.get_values(options, :image),
          verbose: options[:verbose] || false,
          json: options[:json] || false,
          color: color
        ]}}
    end
  end

  defp color(nil), do: {:ok, :auto}
  defp color("auto"), do: {:ok, :auto}
  defp color("always"), do: {:ok, :always}
  defp color("never"), do: {:ok, :never}

  defp color(value), do: {:error, "unknown color: #{value} (expected #{Enum.join(@colors, ", ")})"}

  @doc "The text `--help` prints."
  def help_text do
    """
    condukt — a coding agent

    Usage:
      condukt                          Start the terminal interface
      condukt -p <prompt>              Run one task without the interface
      condukt exec [prompt]            Run one task; reads standard input when the prompt is omitted
      condukt exec -i shot.png "..."   Run one task with an image attached
      condukt connect openrouter       Connect OpenRouter, in the browser or with --api-key
      condukt acp                      Serve the Agent Client Protocol over standard input and output
      condukt files                    List files at the workspace root
      condukt read <path>              Read a workspace file
      condukt import-pi-credentials    Copy the OpenRouter credential from Pi without printing it

    Options:
      -p, --prompt <prompt>  Submit a prompt without starting the terminal interface
      -i, --image <path>     Attach an image to the task; repeat for more than one
          --api-key <key>    OpenRouter credential; prefer CONDUKT_OPENROUTER_API_KEY for scripts
          --cwd <path>       Directory in which tools run (default: the current directory)
      -v, --verbose          Include tool activity on standard error
          --json             Print the final response as machine-readable data
          --color <choice>   auto, always, or never
      -h, --help             Show this message
          --version          Show the version
    """
  end
end
