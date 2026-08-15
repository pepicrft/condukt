defmodule Condukt.CLI.Headless do
  @moduledoc """
  Non-interactive execution for scripts, continuous integration, and pipes.

  One task runs to completion and only the final response reaches standard
  output, so `condukt exec ... | …` composes with other tools. Tool activity is
  available on standard error behind `--verbose`, where it cannot corrupt the
  result a caller is parsing.
  """

  alias Condukt.CLI.OpenRouter
  alias Condukt.CLI.Session
  alias Condukt.CLI.Syntax

  @doc """
  Runs one task and writes the final response.

  ## Options

    * `:prompt` - the task; read from standard input when absent
    * `:api_key` - OpenRouter key; falls back to `CONDUKT_OPENROUTER_API_KEY`
      and then to the saved credential
    * `:cwd` - workspace root (default: the current directory)
    * `:verbose` - print tool activity to standard error
    * `:json` - print the response as machine-readable data
    * `:color` - `:auto`, `:always`, or `:never`
  """
  def run(opts) do
    with {:ok, prompt} <- resolve_prompt(Keyword.get(opts, :prompt)),
         {:ok, root} <- resolve_root(Keyword.get(opts, :cwd)),
         {:ok, api_key} <- resolve_api_key(Keyword.get(opts, :api_key)),
         {:ok, session} <- start_session(api_key, root),
         {:ok, response} <- run_turn(session, prompt, Keyword.get(opts, :verbose, false)) do
      write_response(response, opts)
    end
  end

  defp resolve_prompt(prompt) when is_binary(prompt) do
    if String.trim(prompt) == "", do: {:error, "a prompt is required"}, else: {:ok, prompt}
  end

  defp resolve_prompt(nil) do
    # A terminal on standard input means nothing was piped in, so waiting for a
    # read would hang instead of telling the user what to do.
    if terminal_stdin?() do
      {:error, "a prompt is required; use `condukt exec <prompt>`, `condukt -p <prompt>`, or pipe it on standard input"}
    else
      case IO.read(:stdio, :eof) do
        data when is_binary(data) -> resolve_prompt(data)
        _other -> {:error, "could not read prompt from standard input"}
      end
    end
  end

  defp resolve_root(nil), do: {:ok, File.cwd!()}

  defp resolve_root(root) do
    if File.dir?(root), do: {:ok, root}, else: {:error, "workspace does not exist: #{root}"}
  end

  defp resolve_api_key(key) when is_binary(key) and key != "", do: {:ok, key}

  defp resolve_api_key(_key) do
    case System.get_env("CONDUKT_OPENROUTER_API_KEY") do
      key when is_binary(key) and key != "" -> {:ok, key}
      _other -> saved_api_key()
    end
  end

  defp saved_api_key do
    case OpenRouter.load_key() do
      {:ok, key} when is_binary(key) ->
        {:ok, key}

      {:ok, nil} ->
        {:error, "not connected; run `condukt connect openrouter --api-key <key>` or set CONDUKT_OPENROUTER_API_KEY"}

      {:error, reason} ->
        {:error, "could not read the saved OpenRouter credential: #{inspect(reason)}"}
    end
  end

  defp start_session(api_key, root) do
    case Session.start(api_key, cwd: root) do
      {:ok, session} -> {:ok, session}
      {:error, reason} -> {:error, "could not start the agent session: #{inspect(reason)}"}
    end
  end

  defp run_turn(session, prompt, verbose?) do
    session
    |> Condukt.Session.stream(prompt)
    |> Enum.reduce({[], nil}, fn event, {text, error} ->
      if verbose?, do: print_event(event)

      case event do
        {:text, chunk} -> {[chunk | text], error}
        {:error, reason} -> {text, error || reason}
        _other -> {text, error}
      end
    end)
    |> case do
      {_text, reason} when not is_nil(reason) -> {:error, OpenRouter.describe_turn_error(reason)}
      {text, nil} -> {:ok, text |> Enum.reverse() |> Enum.join()}
    end
  end

  defp print_event({:text, text}), do: IO.puts(:stderr, "assistant: #{text}")

  defp print_event({:tool_call, name, _id, arguments}), do: IO.puts(:stderr, "tool call: #{name} #{encode(arguments)}")

  defp print_event({:tool_result, _id, output}), do: IO.puts(:stderr, "tool result: #{output}")

  defp print_event({:error, reason}), do: IO.puts(:stderr, "error: #{inspect(reason)}")

  defp print_event(_event), do: :ok

  defp encode(value) when is_binary(value), do: value
  defp encode(value) when is_map(value) or is_list(value), do: JSON.encode!(value)
  defp encode(value), do: inspect(value)

  defp write_response(response, opts) do
    if Keyword.get(opts, :json, false) do
      IO.puts(JSON.encode!(%{response: response}))
    else
      IO.puts(render(response, Keyword.get(opts, :color, :auto)))
    end

    :ok
  end

  @doc "Applies terminal colour to a response according to the colour choice."
  def render(response, :never), do: response
  def render(response, :always), do: Syntax.highlight_markdown(response)

  def render(response, :auto) do
    if terminal_stdout?(), do: Syntax.highlight_markdown(response), else: response
  end

  @doc """
  Whether a standard stream is attached to a terminal.

  `:prim_tty.isatty/1` answers for the operating system handle rather than for
  the BEAM's io server, which is what decides whether output is being read by a
  person or by a pipe.
  """
  def terminal?(stream), do: :prim_tty.isatty(stream) == true

  defp terminal_stdout?, do: terminal?(:stdout)

  defp terminal_stdin?, do: terminal?(:stdin)
end
