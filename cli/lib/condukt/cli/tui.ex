defmodule Condukt.CLI.TUI do
  @moduledoc """
  The interactive terminal interface.

  This module owns everything the state machine in `Condukt.CLI.App` cannot: the
  session process, the browser sign-in listener, the footer refresh, and the
  frame the renderer paints. Transitions come back from `App` as a state and a
  list of effects, which `run_effects/2` carries out here.
  """

  use ExRatatui.App

  alias Condukt.CLI.App
  alias Condukt.CLI.Browser
  alias Condukt.CLI.Clipboard
  alias Condukt.CLI.Footer
  alias Condukt.CLI.Input
  alias Condukt.CLI.OAuth
  alias Condukt.CLI.OpenRouter
  alias Condukt.CLI.Session
  alias Condukt.CLI.Theme
  alias Condukt.CLI.Width
  alias ExRatatui.Event.Key
  alias ExRatatui.Event.Mouse
  alias ExRatatui.Event.Paste
  alias ExRatatui.Layout
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Text.Line
  alias ExRatatui.Text.Span
  alias ExRatatui.Widgets.Block
  alias ExRatatui.Widgets.Paragraph

  @slash_menu_height 5
  # top border + content + bottom border
  @prompt_height 3
  @footer_height 1
  @progress_interval 80

  @doc """
  Builds the initial interface state.

  ## Options

    * `:cwd` - workspace root (default: the current directory)
    * `:browser` - one-argument function that opens a URL
    * `:restore_session` - one-argument function of the workspace root returning
      `{connected?, session, warnings}`; the seam tests use to avoid reading the
      real credential store
    * `:footer_refresh` - set to `false` to leave the footer static
  """
  @impl ExRatatui.App
  def mount(opts) do
    browser = Keyword.get(opts, :browser, &Browser.open/1)
    cwd = Keyword.get_lazy(opts, :cwd, &File.cwd!/0)
    restore = Keyword.get(opts, :restore_session, &restore_session/1)
    {connected?, session, warnings} = restore.(cwd)

    state = %{
      app: App.new(working_dir: cwd, connected?: connected?, warnings: warnings),
      session: session,
      browser: browser,
      login: nil,
      cwd: cwd,
      assistant_buffer: "",
      tool_names: %{},
      busy_since: nil,
      connect_ref: nil
    }

    if Keyword.get(opts, :footer_refresh, true), do: schedule_footer_refresh(0)
    {:ok, state}
  end

  defp restore_session(cwd) do
    case OpenRouter.load_key() do
      {:ok, nil} ->
        {false, nil, []}

      {:ok, key} ->
        case Session.start(key, cwd: cwd) do
          {:ok, session} ->
            {true, session, []}

          {:error, reason} ->
            {false, nil, ["Could not start the agent session: #{inspect(reason)}"]}
        end

      {:error, reason} ->
        {false, nil,
         [
           "Could not restore the saved OpenRouter connection: #{inspect(reason)}. Run /connect to sign in again."
         ]}
    end
  end

  # ============================================================================
  # Events
  # ============================================================================

  @impl ExRatatui.App
  def handle_event(%Key{} = key, state) do
    case Input.handle_key(state.app, key) do
      {:continue, app, effects} -> run_effects(%{state | app: app}, effects)
      {:stop, app, _effects} -> {:stop, %{state | app: app}}
    end
  end

  # The terminal's own paste arrives here already decoded. Without this clause a
  # paste did nothing at all.
  def handle_event(%Paste{content: content}, state) do
    {:noreply, %{state | app: App.insert_text(state.app, content)}}
  end

  def handle_event(%Mouse{kind: "scroll_up"}, state) do
    {:noreply, %{state | app: App.scroll_document_up(state.app)}}
  end

  def handle_event(%Mouse{kind: "scroll_down"}, state) do
    {:noreply, %{state | app: App.scroll_document_down(state.app)}}
  end

  def handle_event(_event, state), do: {:noreply, state}

  # ============================================================================
  # Background work
  # ============================================================================

  @impl ExRatatui.App
  def handle_info({:agent_event, event}, state), do: {:noreply, apply_agent_event(state, event)}

  def handle_info({:agent_done, _result}, state) do
    state = flush_assistant_buffer(state)
    {:noreply, %{state | app: %{state.app | pending: false}, busy_since: nil, tool_names: %{}}}
  end

  # Only the attempt currently in flight may report a result. A cancelled
  # attempt keeps running to completion in its task, and without this guard its
  # late reply would connect an interface the user had already backed out of.
  def handle_info({:connection_result, reference, result}, %{connect_ref: reference} = state) do
    apply_connection_result(%{state | connect_ref: nil}, result)
  end

  def handle_info({:connection_result, _reference, _result}, state), do: {:noreply, state}

  def handle_info({:clipboard, {:image, image}}, state) do
    {:noreply, %{state | app: App.attach_image(state.app, image)}}
  end

  def handle_info({:clipboard, {:text, text}}, state) do
    {:noreply, %{state | app: App.insert_text(state.app, text)}}
  end

  def handle_info({:clipboard, :empty}, state), do: {:noreply, state}

  def handle_info({:clipboard, {:unavailable, tools}}, state) do
    {:noreply, %{state | app: App.clipboard_unavailable(state.app, tools)}}
  end

  def handle_info({:footer, snapshot}, state) do
    schedule_footer_refresh(Footer.refresh_interval())
    footer = Footer.apply_refresh(state.app.footer, snapshot)
    {:noreply, %{state | app: %{state.app | footer: footer}}}
  end

  def handle_info(:refresh_footer, state) do
    working_dir = state.cwd
    tui = self()

    Task.Supervisor.start_child(Condukt.CLI.TaskSupervisor, fn ->
      send(tui, {:footer, Footer.refresh(working_dir)})
    end)

    {:noreply, state}
  end

  def handle_info(:progress_tick, state) do
    if App.busy?(state.app), do: schedule_progress_tick()
    {:noreply, state}
  end

  # A browser sign-in reports its outcome as a bare message tagged with the
  # reference the login was started with. The key it produces still has to be
  # validated and turned into a session, which is a network call, so it goes to
  # a task rather than running here and freezing the frame loop, cancel key
  # included.
  def handle_info({reference, {:ok, key}}, %{login: %OAuth{ref: reference}} = state) when is_reference(reference) do
    {:noreply, start_connect_task(%{state | login: nil}, key)}
  end

  def handle_info({reference, {:error, message}}, %{login: %OAuth{ref: reference}} = state)
      when is_reference(reference) do
    apply_connection_result(%{state | login: nil}, {:error, message})
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp apply_connection_result(state, {:ok, session}) do
    {:noreply, %{state | session: session, app: App.connection_result(state.app, :ok), busy_since: nil}}
  end

  defp apply_connection_result(state, {:error, message}) do
    {:noreply, %{state | app: App.connection_result(state.app, {:error, message}), busy_since: nil}}
  end

  # ============================================================================
  # Agent events
  # ============================================================================

  # The session streams assistant text in deltas. Buffering them and flushing on
  # the next structural event keeps one model turn as one transcript block
  # rather than one block per token.
  defp apply_agent_event(state, {:text, chunk}) do
    %{state | assistant_buffer: state.assistant_buffer <> chunk}
  end

  defp apply_agent_event(state, {:tool_call, name, id, arguments}) do
    state = flush_assistant_buffer(state)

    %{
      state
      | app: App.push_tool_call(state.app, name, arguments),
        tool_names: Map.put(state.tool_names, id, name)
    }
  end

  defp apply_agent_event(state, {:tool_result, id, content}) do
    name = Map.get(state.tool_names, id, "tool")
    %{state | app: App.push_tool_result(state.app, name, content)}
  end

  defp apply_agent_event(state, :turn_end), do: flush_assistant_buffer(state)

  defp apply_agent_event(state, {:error, reason}) do
    state = flush_assistant_buffer(state)
    app = App.push_error(state.app, "Request failed: #{OpenRouter.describe_turn_error(reason)}")
    %{state | app: %{app | pending: false}, busy_since: nil}
  end

  # Reasoning is requested but excluded from the transcript, matching what the
  # provider is asked to return.
  defp apply_agent_event(state, _event), do: state

  defp flush_assistant_buffer(%{assistant_buffer: ""} = state), do: state

  defp flush_assistant_buffer(state) do
    %{state | app: App.push_model_message(state.app, state.assistant_buffer), assistant_buffer: ""}
  end

  # ============================================================================
  # Effects
  # ============================================================================

  @doc """
  Carries out the effects a transition asked for.

  Effects are the only place the interface reaches outside itself, which is what
  keeps `Condukt.CLI.App` free of processes and I/O.
  """
  def run_effects(state, effects), do: {:noreply, Enum.reduce(effects, state, &run_effect(&2, &1))}

  defp run_effect(state, {:open_browser, url}) do
    state.browser.(url)
    state
  end

  defp run_effect(state, {:submit_prompt, prompt, images}) do
    Session.stream_to(state.session, prompt, self(), images: images)
    schedule_progress_tick()
    %{state | busy_since: now(), assistant_buffer: "", tool_names: %{}}
  end

  defp run_effect(state, {:connect_with_key, key}), do: start_connect_task(state, key)

  defp run_effect(state, {:start_oauth, _provider}) do
    case OAuth.start_login() do
      {:ok, login} ->
        {app, effects} = App.login_started(state.app, login.authorize_url)
        schedule_progress_tick()
        {:noreply, state} = run_effects(%{state | app: app, login: login, busy_since: now()}, effects)
        state

      {:error, message} ->
        %{state | app: App.login_failed(state.app, message)}
    end
  end

  # Cancelling stops the browser listener and disowns whatever attempt is in
  # flight. The task itself is left to finish: its reply no longer matches
  # `connect_ref`, so it is dropped on arrival.
  defp run_effect(state, :cancel_connection) do
    if state.login, do: OAuth.cancel(state.login)
    %{state | login: nil, busy_since: nil, connect_ref: nil}
  end

  # Reading the clipboard shells out, and on macOS that is AppleScript, which is
  # slow enough to drop frames. It belongs in a task like every other command
  # the interface runs.
  defp run_effect(state, :paste_clipboard) do
    tui = self()

    Task.Supervisor.start_child(Condukt.CLI.TaskSupervisor, fn ->
      send(tui, {:clipboard, read_clipboard()})
    end)

    state
  end

  defp run_effect(state, :exit), do: state

  defp run_effect(state, _effect), do: state

  # Validating a key, saving it, and starting a session are all slow enough to
  # be visible, so they happen off the frame loop and report back as a message.
  defp start_connect_task(state, key) do
    tui = self()
    cwd = state.cwd
    reference = make_ref()

    Task.Supervisor.start_child(Condukt.CLI.TaskSupervisor, fn ->
      send(tui, {:connection_result, reference, connect_with_key(key, cwd)})
    end)

    schedule_progress_tick()
    %{state | busy_since: now(), connect_ref: reference}
  end

  @doc """
  Reads whatever the clipboard is holding.

  An image wins over text, because a clipboard carrying an image often carries a
  filename alongside it and the image is what the user meant to paste.
  """
  def read_clipboard do
    case Clipboard.read_image() do
      {:ok, image} -> {:image, image}
      :none -> clipboard_text()
    end
  end

  defp clipboard_text do
    case Clipboard.read_text() do
      {:ok, text} -> {:text, text}
      :none -> empty_clipboard()
    end
  end

  # Nothing came back, which is either an empty clipboard or a host with no way
  # to read one. Only the second is worth telling the user about.
  defp empty_clipboard do
    case Clipboard.missing_tooling() do
      nil -> :empty
      tools -> {:unavailable, tools}
    end
  end

  @doc """
  Validates a key, saves it, and starts a session for it.

  Runs in a task: it makes a network call and touches the credential store, so
  it must not happen on the frame loop.
  """
  def connect_with_key(key, cwd) do
    with :ok <- OpenRouter.validate(key),
         :ok <- save_key(key) do
      start_session(key, cwd)
    end
  end

  defp save_key(key) do
    case OpenRouter.save_key(key) do
      :ok -> :ok
      {:error, reason} -> {:error, "Failed to save the OpenRouter key: #{inspect(reason)}"}
    end
  end

  defp start_session(key, cwd) do
    case Session.start(key, cwd: cwd) do
      {:ok, session} -> {:ok, session}
      {:error, reason} -> {:error, "Could not start the agent session: #{inspect(reason)}"}
    end
  end

  defp schedule_footer_refresh(delay), do: Process.send_after(self(), :refresh_footer, delay)

  defp schedule_progress_tick, do: Process.send_after(self(), :progress_tick, @progress_interval)

  defp now, do: System.monotonic_time(:millisecond)

  # ============================================================================
  # Rendering
  # ============================================================================

  @impl ExRatatui.App
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    state.app
    |> layout(area)
    |> Enum.flat_map(fn {slot, rect} -> widgets_for(slot, rect, state) end)
  end

  @doc """
  Splits the frame into the slots the current mode needs.

  Guided menus (authentication method, provider) suppress the prompt because the
  menu itself is the input surface. API-key entry keeps the prompt so the user
  can type the key, and so does normal mode.
  """
  def layout(%App{} = app, %Rect{} = area) do
    in_menu? = App.in_menu?(app)
    slash? = App.show_commands?(app) and not in_menu?

    slots =
      [{:document, {:min, 0}}] ++
        cond do
          in_menu? -> [{:connect_menu, {:length, App.menu_height(app)}}]
          slash? -> [{:slash_menu, {:length, @slash_menu_height}}]
          true -> []
        end ++
        if(in_menu?, do: [], else: [{:prompt, {:length, @prompt_height}}]) ++
        [{:footer, {:length, @footer_height}}]

    rects = Layout.split(area, :vertical, Enum.map(slots, fn {_slot, constraint} -> constraint end))

    slots |> Enum.map(fn {slot, _constraint} -> slot end) |> Enum.zip(rects)
  end

  defp widgets_for(:document, rect, state) do
    [
      {%Paragraph{
         text: App.document_lines(state.app),
         scroll: {App.document_scroll(state.app, rect.height), 0}
       }, rect}
    ]
  end

  defp widgets_for(:connect_menu, rect, state) do
    [
      {%Block{borders: [:top, :bottom], border_style: Theme.border()}, rect},
      {%Paragraph{text: App.menu_lines(state.app)}, inner(rect)}
    ]
  end

  defp widgets_for(:slash_menu, rect, state) do
    [{%Paragraph{text: App.slash_menu_lines(state.app)}, rect}]
  end

  defp widgets_for(:prompt, rect, state) do
    body =
      if App.busy?(state.app) do
        # While a request is in flight the prompt stays calm and the activity
        # indicator moves along its top border, where it does not compete with
        # the conversation transcript.
        %Line{spans: []}
      else
        prompt_line(state.app)
      end

    border = {%Block{borders: [:top, :bottom], border_style: Theme.border()}, rect}
    content = {%Paragraph{text: body}, inner(rect)}

    if App.busy?(state.app) do
      progress = {
        %Paragraph{text: progress_line(rect.width, elapsed(state))},
        %Rect{x: rect.x, y: rect.y, width: rect.width, height: 1}
      }

      [border, progress, content]
    else
      [border, content]
    end
  end

  defp widgets_for(:footer, rect, state) do
    [{%Paragraph{text: Footer.lines(state.app.footer, rect.width)}, rect}]
  end

  # A block with top and bottom borders leaves everything between them free.
  defp inner(%Rect{} = rect) do
    %Rect{x: rect.x, y: rect.y + 1, width: rect.width, height: max(rect.height - 2, 0)}
  end

  defp elapsed(%{busy_since: nil}), do: 0
  defp elapsed(%{busy_since: started_at}), do: System.monotonic_time(:millisecond) - started_at

  @doc """
  The prompt's content line: the mode marker, the typed text, and a block cursor.

  The cursor is drawn as a reversed cell rather than moved with a terminal
  escape, so it stays inside the frame the renderer diffs.
  """
  def prompt_line(%App{} = app) do
    %Line{
      spans: [
        %Span{content: App.prompt_prefix(app), style: Theme.prompt_prefix()},
        %Span{content: app.input},
        %Span{content: " ", style: %Style{modifiers: [:reversed]}}
      ]
    }
  end

  @doc """
  A short accent segment travelling along the prompt's top rule while work is in
  flight. It replaces what would otherwise be a permanent "thinking" entry in
  the transcript.
  """
  def progress_line(width, elapsed_ms) when width <= 0 or elapsed_ms < 0, do: %Line{spans: []}

  def progress_line(width, elapsed_ms) do
    segment_width = 6
    position = Integer.mod(div(elapsed_ms, @progress_interval) + 1, width + segment_width)
    start = max(position - (segment_width - 1), 0)
    finish = min(position, width)

    spans =
      [
        start > 0 && %Span{content: String.duplicate("─", start), style: Theme.border()},
        finish > start &&
          %Span{content: String.duplicate("━", finish - start), style: Theme.activity_marker()},
        finish < width &&
          %Span{content: String.duplicate("─", width - finish), style: Theme.border()}
      ]
      |> Enum.filter(&is_struct(&1, Span))

    %Line{spans: spans}
  end

  @doc "Display width of the prompt's content, used when placing the cursor."
  def prompt_content_width(%App{} = app) do
    Width.of(App.prompt_prefix(app)) + Width.of(app.input)
  end
end
