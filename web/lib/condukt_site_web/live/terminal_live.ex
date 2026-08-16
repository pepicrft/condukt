defmodule ConduktSiteWeb.TerminalLive do
  @moduledoc """
  The terminal on the home page: the loop on the server, the tools in the page.

  The visitor signs in with OpenRouter through the existing flow, which leaves
  the credential in the Phoenix session. This reads it once at mount and hands
  it to a `Condukt.Session`, so the key never reaches the page and inference is
  still billed to whoever asked for it.

  What the agent can do comes from the other direction. The page declares its
  tools when it connects, and this holds the socket open in the middle: a tool
  call goes out as an event, the browser runs it, the result comes back as
  another, and the process waiting inside `ConduktSite.BrowserTools` is handed
  the answer. Pending calls live in this LiveView's own state, so one visitor's
  page can only ever resolve one visitor's calls.
  """

  use ConduktSiteWeb, :live_view

  alias ConduktSite.BrowserTools
  alias ConduktSite.Conversation
  alias ConduktSite.Repository

  @impl Phoenix.LiveView
  def mount(_params, session, socket) do
    key = session["openrouter_key"]

    socket =
      assign(socket,
        connected?: not is_nil(key),
        api_key: key,
        session_id: nil,
        prompt: "",
        pending?: false,
        entries: [],
        pending_calls: %{},
        model: Application.fetch_env!(:condukt_site, :openrouter_model),
        source: Repository.source()
      )

    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("tools", %{"tools" => declarations}, socket) do
    {:noreply, ensure_session(socket, BrowserTools.build(declarations, self()))}
  end

  def handle_event("update", %{"prompt" => prompt}, socket) do
    {:noreply, assign(socket, :prompt, prompt)}
  end

  def handle_event("submit", _params, %{assigns: %{pending?: true}} = socket) do
    {:noreply, socket}
  end

  # The submitted value wins over the last change event. Relying on the change
  # having arrived first loses anything the browser filled in and sent in one
  # go, which is what an autofill or a fast return key does.
  def handle_event("submit", params, socket) do
    prompt = params |> Map.get("prompt", socket.assigns.prompt) |> String.trim()

    if prompt == "" do
      {:noreply, socket}
    else
      {:noreply, socket |> ensure_session([]) |> submit(prompt)}
    end
  end

  # The browser answered a tool call. An unknown token is dropped rather than
  # trusted: the map holds only what this page was actually asked for.
  def handle_event("tool_result", %{"token" => token} = payload, socket) do
    case Map.pop(socket.assigns.pending_calls, token) do
      {nil, _pending} ->
        {:noreply, socket}

      {{caller, ref}, pending} ->
        send(caller, {:browser_tool_result, ref, interpret(payload)})
        {:noreply, assign(socket, :pending_calls, pending)}
    end
  end

  defp interpret(%{"ok" => true, "result" => result}), do: {:ok, result}
  defp interpret(%{"error" => message}) when is_binary(message), do: {:error, message}
  defp interpret(_payload), do: {:error, "the browser returned a malformed tool result"}

  # Started on the page's first word rather than at mount, because the tools
  # belong to the page and a session is worth nothing without them. A static
  # render, which happens for every crawler, never reaches here.
  defp ensure_session(%{assigns: %{session_id: id}} = socket, _tools) when is_binary(id),
    do: socket

  defp ensure_session(%{assigns: %{api_key: nil}} = socket, _tools), do: socket

  defp ensure_session(socket, tools) do
    case Conversation.start(socket.assigns.api_key, tools) do
      {:ok, session_id} ->
        assign(socket, :session_id, session_id)

      {:error, _reason} ->
        put_entry(socket, :error, "The agent could not be started. Try reloading the page.")
    end
  end

  defp submit(%{assigns: %{session_id: nil}} = socket, _prompt) do
    put_entry(socket, :error, "The agent could not be started. Try reloading the page.")
  end

  defp submit(socket, prompt) do
    socket = socket |> put_entry(:prompt, prompt) |> assign(prompt: "", pending?: true)

    case Conversation.submit(socket.assigns.session_id, prompt, self()) do
      :ok ->
        socket

      {:error, :no_session} ->
        socket
        |> put_entry(:error, "The agent session ended. Reload the page to start another.")
        |> assign(pending?: false)
    end
  end

  @impl Phoenix.LiveView
  def handle_info({:agent, {:text, chunk}}, socket), do: {:noreply, append_text(socket, chunk)}

  def handle_info({:agent, {:error, reason}}, socket) do
    {:noreply, socket |> put_entry(:error, describe(reason)) |> assign(pending?: false)}
  end

  def handle_info({:agent, :done}, socket), do: {:noreply, assign(socket, :pending?, false)}

  # Thinking, tool results, and the turn markers carry nothing this surface
  # shows. Matching them explicitly would mean listing every event the library
  # will ever emit. Tool calls are shown when they are dispatched below, which
  # is also where the arguments are known to have survived validation.
  def handle_info({:agent, _event}, socket), do: {:noreply, socket}

  # A tool the agent called, on its way to the browser. The caller is parked in
  # a receive until the page answers or `BrowserTools` gives up on it.
  def handle_info({:browser_tool, caller, ref, name, args}, socket) do
    token = token()

    socket =
      socket
      |> assign(:pending_calls, Map.put(socket.assigns.pending_calls, token, {caller, ref}))
      |> put_entry(:tool, name)
      |> push_event("condukt:tool", %{token: token, name: name, args: args})

    {:noreply, socket}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  # There is no terminate/2 stopping the session on purpose. A lost connection
  # kills this process without running it, which is how most of these end, so
  # `ConduktSite.Conversation` monitors instead and covers both endings.

  # Assistant text arrives in fragments. Appending to the open reply keeps one
  # answer as one block rather than one entry per token.
  defp append_text(socket, chunk) do
    case socket.assigns.entries do
      [%{kind: :reply, text: text} = entry | rest] ->
        assign(socket, :entries, [%{entry | text: text <> chunk} | rest])

      entries ->
        assign(socket, :entries, [%{kind: :reply, text: chunk, id: entry_id()} | entries])
    end
  end

  defp put_entry(socket, kind, text) do
    assign(socket, :entries, [%{kind: kind, text: text, id: entry_id()} | socket.assigns.entries])
  end

  defp entry_id, do: System.unique_integer([:positive, :monotonic])

  defp token, do: 12 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  defp describe(reason) when is_binary(reason), do: reason
  defp describe(reason), do: inspect(reason)

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <section id="terminal" data-part="terminal-live" phx-hook="ConduktTerminal">
      <header data-part="terminal-header">
        <span data-part="terminal-title">Condukt</span>
        <span data-part="terminal-meta">{@model} · reading {@source.repository}</span>
      </header>

      <div data-part="terminal-body">
        <ol data-part="terminal-entries">
          <li :for={entry <- Enum.reverse(@entries)} id={"entry-#{entry.id}"} data-kind={entry.kind}>
            <span :if={entry.kind == :prompt} data-part="marker">&gt;</span>
            <span :if={entry.kind == :tool} data-part="marker">tool</span>
            <span data-part="entry-text">{entry.text}</span>
          </li>
        </ol>
      </div>

      <footer data-part="terminal-footer">
        <form :if={@connected?} phx-submit="submit" phx-change="update">
          <label for="prompt" class="sr-only">Ask about Condukt's source</label>
          <input
            id="prompt"
            name="prompt"
            value={@prompt}
            autocomplete="off"
            disabled={@pending?}
            placeholder={if @pending?, do: "Working…", else: "Ask about Condukt's source"}
          />
          <button type="submit" disabled={@pending? or @prompt == ""}>Send</button>
        </form>

        <p :if={!@connected?} data-part="terminal-signin">
          <a href={~p"/auth/openrouter?#{%{return_to: "/#terminal"}}"}>Connect OpenRouter</a>
          to run a real Condukt session. The agent runs on this server and reads {@source.repository} from your browser; inference is billed to your account.
        </p>
      </footer>
    </section>
    """
  end
end
