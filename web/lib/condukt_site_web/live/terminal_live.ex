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

  ## The form is not a LiveView form

  Everything below the transcript is markup this never re-renders, driven by the
  `ConduktTerminal` hook. The controls are Noora custom elements holding their
  own state, and a server-side patch is a good way to lose what someone is
  halfway through typing. The transcript above it is the opposite: it is
  rendered here on every fragment, which is the whole reason this is a LiveView.
  """

  use ConduktSiteWeb, :live_view

  alias ConduktSite.BrowserTools
  alias ConduktSite.Conversation
  alias ConduktSite.Repository

  @markdown_options [
    extension: [table: true, strikethrough: true, autolink: true],
    # Model output. Raw HTML in it is text, not markup.
    render: [unsafe: false],
    syntax_highlight: nil
  ]

  @impl Phoenix.LiveView
  def mount(_params, session, socket) do
    key = session["openrouter_key"]

    socket =
      assign(socket,
        connected?: not is_nil(key),
        api_key: key,
        session_id: nil,
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

  def handle_event("submit", _params, %{assigns: %{pending?: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("submit", %{"prompt" => prompt}, socket) do
    case String.trim(prompt) do
      "" -> {:noreply, socket}
      trimmed -> {:noreply, socket |> ensure_session([]) |> submit(trimmed)}
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
    socket = socket |> put_entry(:user, prompt) |> busy(true)

    case Conversation.submit(socket.assigns.session_id, prompt, self()) do
      :ok ->
        socket

      {:error, :no_session} ->
        socket
        |> put_entry(:error, "The agent session ended. Reload the page to start another.")
        |> busy(false)
    end
  end

  @impl Phoenix.LiveView
  def handle_info({:agent, {:text, chunk}}, socket), do: {:noreply, append_text(socket, chunk)}

  def handle_info({:agent, {:error, reason}}, socket) do
    {:noreply, socket |> put_entry(:error, describe(reason)) |> busy(false)}
  end

  def handle_info({:agent, :done}, socket), do: {:noreply, busy(socket, false)}

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
      |> put_activity(name)
      |> push_event("condukt:tool", %{token: token, name: name, args: args})

    {:noreply, socket}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  # There is no terminate/2 stopping the session on purpose. A lost connection
  # kills this process without running it, which is how most of these end, so
  # `ConduktSite.Conversation` monitors instead and covers both endings.

  # The form is not re-rendered, so its busy state is told to the page rather
  # than patched into it.
  defp busy(socket, pending?) do
    socket |> assign(:pending?, pending?) |> push_event("condukt:busy", %{busy: pending?})
  end

  # Assistant text arrives in fragments. Appending to the open reply keeps one
  # answer as one block rather than one entry per token.
  defp append_text(socket, chunk) do
    case socket.assigns.entries do
      [%{kind: :assistant, text: text} = entry | rest] ->
        assign(socket, :entries, [%{entry | text: text <> chunk} | rest])

      entries ->
        assign(socket, :entries, [
          %{kind: :assistant, text: chunk, id: entry_id()} | entries
        ])
    end
  end

  # Consecutive tool calls collect into one line of badges rather than one
  # entry each, which is what a turn that reads four files looks like.
  defp put_activity(socket, name) do
    case socket.assigns.entries do
      [%{kind: :tools, activities: activities} = entry | rest] ->
        assign(socket, :entries, [%{entry | activities: activities ++ [name]} | rest])

      entries ->
        assign(socket, :entries, [
          %{kind: :tools, activities: [name], id: entry_id()} | entries
        ])
    end
  end

  defp put_entry(socket, kind, text) do
    assign(socket, :entries, [%{kind: kind, text: text, id: entry_id()} | socket.assigns.entries])
  end

  defp entry_id, do: System.unique_integer([:positive, :monotonic])

  defp token, do: 12 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  defp describe(reason) when is_binary(reason), do: reason
  defp describe(reason), do: inspect(reason)

  defp markdown(text), do: text |> MDEx.to_html!(@markdown_options) |> raw()

  defp greeting(true = _connected?, source),
    do:
      "I am a Condukt session running on this server. My tools run in your browser, " <>
        "where I can list directories and read text files from #{source.repository}. " <>
        "What would you like to know?"

  defp greeting(false = _connected?, source),
    do:
      "Connect OpenRouter to start a real Condukt session. The agent loop runs on this " <>
        "server; its tools run in your browser, reading #{source.repository} and nothing else."

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <noora-card
      id="condukt-terminal"
      phx-hook="ConduktTerminal"
      data-part="terminal"
      class="noora-dark"
      title="condukt · github.com/tuist/condukt"
      icon="devices_code"
    >
      <div id="agent-transcript" data-part="agent-transcript" aria-live="polite">
        <div data-part="terminal-entry" data-role="assistant">
          <span data-part="terminal-prompt">condukt</span>
          <div data-part="message-body">
            <div data-part="markdown">{markdown(greeting(@connected?, @source))}</div>
          </div>
        </div>

        <div
          :for={entry <- Enum.reverse(@entries)}
          id={"entry-#{entry.id}"}
          data-part="terminal-entry"
          data-role={if entry.kind == :user, do: "user", else: "assistant"}
        >
          <span data-part="terminal-prompt">
            {if entry.kind == :user, do: "you", else: "condukt"}
          </span>

          <div :if={entry.kind == :tools} data-part="tool-activities">
            <noora-status-badge
              :for={activity <- entry.activities}
              data-part="tool-activity"
              type="dot"
              status="in_progress"
              label={activity}
            >
              {activity}
            </noora-status-badge>
          </div>

          <div :if={entry.kind == :user} data-part="message-body">{entry.text}</div>

          <div :if={entry.kind == :assistant} data-part="message-body">
            <div data-part="markdown">{markdown(entry.text)}</div>
          </div>

          <div :if={entry.kind == :error} data-part="message-body" data-error>{entry.text}</div>
        </div>
      </div>

      <div :if={!@connected?} data-part="agent-connect">
        <noora-alert
          type="secondary"
          status="information"
          size="large"
          title="Connect OpenRouter to continue"
          show-icon
        >
          Your OpenRouter key stays in a browser-inaccessible encrypted session and is used
          only to bill your own inference. The agent reads <code>{@source.repository}</code>
          from your browser.
          <noora-button
            slot="action"
            data-action="connect"
            variant="primary"
            size="large"
            href={~p"/auth/openrouter?#{%{return_to: "/#terminal"}}"}
          >
            Log in with OpenRouter
          </noora-button>
        </noora-alert>
      </div>

      <form :if={@connected?} id="agent-form" data-part="agent-form" data-model={@model}>
        <noora-label label="Ask Condukt about its repository" for="agent-prompt"></noora-label>
        <div data-part="prompt-row">
          <noora-text-area
            id="agent-prompt"
            name="prompt"
            aria-label="Ask Condukt about its repository"
            rows="2"
            max-length="2000"
            show-character-count
            resize="none"
            placeholder="How does the host-driven agent loop work?"
            required
          >
          </noora-text-area>
          <noora-button
            id="agent-submit"
            type="button"
            icon-only
            size="small"
            aria-label="Send message"
          >
            <span aria-hidden="true">↑</span>
          </noora-button>
        </div>
        <div data-part="form-footer">
          <div data-part="form-context" aria-label="Agent configuration">
            <noora-status-badge id="agent-status" type="dot" status="success" label={@model}>
              {@model}
            </noora-status-badge>
          </div>
          <noora-button type="submit" form="disconnect-form" variant="secondary" size="small">
            Disconnect OpenRouter
          </noora-button>
        </div>
      </form>

      <form :if={@connected?} id="disconnect-form" action={~p"/auth/openrouter"} method="post" hidden>
        <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
        <input type="hidden" name="_method" value="delete" />
      </form>
    </noora-card>
    """
  end
end
