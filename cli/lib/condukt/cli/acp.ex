defmodule Condukt.CLI.ACP do
  @moduledoc """
  Headless [Agent Client Protocol](https://agentclientprotocol.com/) server.

  The protocol is JSON-RPC over standard input and output. Keep this module free
  of terminal concerns: an editor owns the user interface while Condukt owns the
  session and its tools.

  Requests are read, handled, and answered in order on a single process. That
  keeps every write to standard output whole, at the cost of not interleaving
  two sessions' turns: a prompt runs to completion before the next request is
  read. Editors drive one prompt at a time per session, so this has not been
  worth a writer process and out-of-order responses.
  """

  alias Condukt.CLI.OpenRouter
  alias Condukt.CLI.Session

  @protocol_version 1
  @agent_name "condukt"

  @doc """
  Serves the protocol on standard input until the client closes the stream.

  ## Options

    * `:version` - the agent version reported during initialization
    * `:cwd` - fallback workspace root when a client creates a session without one
  """
  def run(opts \\ []) do
    serve(%{sessions: %{}, next_session: 0, version: Keyword.get(opts, :version, "0.0.0"), opts: opts})
  end

  defp serve(state) do
    case IO.read(:stdio, :line) do
      :eof -> :ok
      {:error, _reason} -> :ok
      line -> line |> handle_line(state) |> serve()
    end
  end

  defp handle_line(line, state) do
    line
    |> String.trim()
    |> decode()
    |> case do
      {:ok, request} -> dispatch(request, state)
      :skip -> state
    end
  end

  defp decode(""), do: :skip

  defp decode(line) do
    case JSON.decode(line) do
      {:ok, request} when is_map(request) -> {:ok, request}
      _other -> :skip
    end
  end

  @doc """
  Handles one decoded request, writing any response.

  Returns the new server state.
  """
  def dispatch(%{"method" => "initialize", "id" => id}, state) do
    respond(id, %{
      protocolVersion: @protocol_version,
      agentCapabilities: %{},
      agentInfo: %{name: @agent_name, title: "Condukt", version: state.version}
    })

    state
  end

  def dispatch(%{"method" => "session/new", "id" => id} = request, state) do
    number = state.next_session + 1
    session_id = "condukt-#{number}"
    cwd = get_in(request, ["params", "cwd"]) || Keyword.get(state.opts, :cwd) || File.cwd!()

    state = %{
      state
      | next_session: number,
        sessions: Map.put(state.sessions, session_id, start_session(cwd))
    }

    respond(id, %{sessionId: session_id})
    state
  end

  def dispatch(%{"method" => "session/prompt", "id" => id} = request, state) do
    session_id = get_in(request, ["params", "sessionId"])
    prompt = request |> get_in(["params", "prompt"]) |> prompt_text()

    case Map.get(state.sessions, session_id) do
      nil ->
        respond(id, %{stopReason: "refusal"})

      {:error, message} ->
        notify_message(session_id, message)
        respond(id, %{stopReason: "end_turn"})

      session ->
        run_prompt(session, session_id, prompt)
        respond(id, %{stopReason: "end_turn"})
    end

    state
  end

  def dispatch(%{"id" => id, "method" => method}, state) do
    respond_error(id, -32_601, "unsupported method: #{method}")
    state
  end

  # Notifications carry no id and expect no response.
  def dispatch(_request, state), do: state

  defp start_session(cwd) do
    case OpenRouter.load_key() do
      {:ok, key} when is_binary(key) -> start_connected_session(key, cwd)
      {:ok, nil} -> {:error, "Condukt is not connected. Run `condukt connect openrouter --api-key <key>` first."}
      {:error, reason} -> {:error, "Could not load the OpenRouter connection: #{inspect(reason)}"}
    end
  end

  defp start_connected_session(key, cwd) do
    case Session.start(key, cwd: cwd) do
      {:ok, session} -> session
      {:error, reason} -> {:error, "Could not start the agent session: #{inspect(reason)}"}
    end
  end

  defp run_prompt(session, session_id, prompt) do
    session
    |> Condukt.Session.stream(prompt)
    |> Enum.each(fn
      {:text, chunk} -> notify_message(session_id, chunk)
      {:error, reason} -> notify_message(session_id, OpenRouter.describe_turn_error(reason))
      _other -> :ok
    end)
  end

  @doc """
  Flattens a prompt's content blocks into the text the model sees.

  Resource links become Markdown links so the model can still see what the
  editor attached, and unsupported blocks are named rather than dropped
  silently.
  """
  def prompt_text(blocks) when is_list(blocks) do
    Enum.map_join(blocks, "\n", &block_text/1)
  end

  def prompt_text(_blocks), do: ""

  defp block_text(%{"type" => "text", "text" => text}), do: text

  defp block_text(%{"type" => "resource_link", "name" => name, "uri" => uri}), do: "[#{name}](#{uri})"

  defp block_text(_block), do: "[Unsupported prompt content omitted]"

  defp notify_message(session_id, text) do
    write(%{
      jsonrpc: "2.0",
      method: "session/update",
      params: %{
        sessionId: session_id,
        update: %{sessionUpdate: "agent_message_chunk", content: %{type: "text", text: text}}
      }
    })
  end

  defp respond(id, result), do: write(%{jsonrpc: "2.0", id: id, result: result})

  defp respond_error(id, code, message) do
    write(%{jsonrpc: "2.0", id: id, error: %{code: code, message: message}})
  end

  defp write(envelope), do: IO.puts(JSON.encode!(envelope))
end
