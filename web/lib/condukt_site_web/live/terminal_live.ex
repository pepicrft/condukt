defmodule ConduktSiteWeb.TerminalLive do
  @moduledoc """
  The terminal on the home page, driven by a session on the server.

  The visitor signs in with OpenRouter through the existing flow, which leaves
  the credential in the Phoenix session. This reads it once at mount and hands
  it to a `Condukt.Session`, so the key never reaches the page and the agent
  never leaves the server.

  Streaming is the reason this is a LiveView rather than a form: a turn emits
  text, tool calls and tool results as it goes, and each one is rendered as it
  arrives.
  """

  use ConduktSiteWeb, :live_view

  alias ConduktSite.Conversation
  alias ConduktSite.Repository

  @impl Phoenix.LiveView
  def mount(_params, session, socket) do
    key = session["openrouter_key"]

    socket =
      socket
      |> assign(
        connected?: not is_nil(key),
        session_id: nil,
        prompt: "",
        pending?: false,
        entries: [],
        model: Application.fetch_env!(:condukt_site, :openrouter_model),
        source: Repository.source()
      )
      |> start_conversation(key)

    {:ok, socket}
  end

  # Only a connected mount starts a session. The first, static render happens
  # for every page load including crawlers, and starting a process there would
  # spawn one per visit that nothing ever talks to.
  defp start_conversation(socket, nil), do: socket

  defp start_conversation(socket, key) do
    if connected?(socket) do
      case Conversation.start(key) do
        {:ok, session_id} ->
          assign(socket, :session_id, session_id)

        {:error, _reason} ->
          put_entry(socket, :error, "The agent could not be started. Try reloading.")
      end
    else
      socket
    end
  end

  @impl Phoenix.LiveView
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
      {:noreply, submit(socket, prompt)}
    end
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

  def handle_info({:agent, {:tool_call, name, _id, _args}}, socket) do
    {:noreply, put_entry(socket, :tool, name)}
  end

  def handle_info({:agent, {:error, reason}}, socket) do
    {:noreply, socket |> put_entry(:error, describe(reason)) |> assign(pending?: false)}
  end

  def handle_info({:agent, :done}, socket), do: {:noreply, assign(socket, :pending?, false)}

  # Thinking, tool results, and the turn markers carry nothing this surface
  # shows. Matching them explicitly would mean listing every event the library
  # will ever emit.
  def handle_info({:agent, _event}, socket), do: {:noreply, socket}

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl Phoenix.LiveView
  def terminate(_reason, socket) do
    Conversation.stop(socket.assigns[:session_id])
    :ok
  end

  # Assistant text arrives in fragments. Appending to the open reply keeps one
  # answer as one block rather than one per token.
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

  defp describe(reason) when is_binary(reason), do: reason
  defp describe(reason), do: inspect(reason)

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <section id="terminal" data-part="terminal-live">
      <header data-part="terminal-header">
        <span data-part="terminal-title">Condukt</span>
        <span data-part="terminal-meta">{@model} · reading {@source.repository}</span>
      </header>

      <div data-part="terminal-body" id="terminal-body">
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
          to run a real Condukt session. Inference is billed to your account; the agent reads {@source.repository} and nothing else.
        </p>
      </footer>
    </section>
    """
  end
end
