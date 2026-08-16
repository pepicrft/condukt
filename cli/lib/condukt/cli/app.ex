defmodule Condukt.CLI.App do
  @moduledoc """
  The terminal interface's state machine.

  Every function here is pure: transitions return the new state together with a
  list of effects (`{:open_browser, url}`, `{:submit_prompt, prompt}`, and so
  on) for the host to carry out. Keeping processes, sockets, and HTTP calls out
  of this module is what lets the whole interface be exercised in ordinary
  asynchronous tests, and keeps the frame loop free of blocking work.
  """

  alias Condukt.CLI.Attachment
  alias Condukt.CLI.Clipboard
  alias Condukt.CLI.Commands
  alias Condukt.CLI.Footer
  alias Condukt.CLI.OpenRouter
  alias Condukt.CLI.RichText
  alias Condukt.CLI.Theme
  alias Condukt.CLI.Transcript
  alias Condukt.CLI.Workspace
  alias ExRatatui.Style

  @connect_methods [
    %{value: "account", description: "Sign in with an account"},
    %{value: "api-key", description: "Sign in with an API key"}
  ]

  @providers [%{value: "openrouter", description: "OpenRouter"}]

  @scroll_step 3

  defstruct connected?: false,
            input: "",
            document: [],
            mode: :normal,
            show_commands: false,
            slash_selected: nil,
            should_exit: false,
            pending: false,
            footer: nil,
            user_name: "You",
            model_name: nil,
            working_dir: ".",
            document_scroll_from_bottom: 0,
            attachments: []

  @doc "The rows offered by the authentication-method menu."
  def connect_methods, do: @connect_methods

  @doc "The rows offered by the provider menu."
  def providers, do: @providers

  @doc """
  Builds the interface state shown on launch.

  `connected?` says whether a saved credential was restored; the caller owns
  reading it so this module stays free of filesystem access.
  """
  def new(opts \\ []) do
    working_dir = Keyword.get(opts, :working_dir, ".")
    connected? = Keyword.get(opts, :connected?, false)

    app = %__MODULE__{
      connected?: connected?,
      working_dir: working_dir,
      footer: Footer.new(working_dir),
      user_name: Keyword.get(opts, :user_name, system_user_name()),
      model_name: Keyword.get(opts, :model_name, OpenRouter.model()),
      document: [
        Transcript.styled("Condukt", Theme.title()),
        Transcript.plain("A coding agent"),
        Transcript.blank()
      ]
    }

    app = Enum.reduce(Keyword.get(opts, :warnings, []), app, &push_error(&2, &1))

    if connected? do
      app
    else
      connect_hint =
        RichText.new()
        |> RichText.push_text("Type ")
        |> RichText.push_command("/connect")
        |> RichText.push_text(" to connect your account.")
        |> RichText.to_line()

      %{app | document: app.document ++ [connect_hint]}
    end
  end

  @doc "A bare state with no launch banner. Used by tests and by `new/1`."
  def empty(opts \\ []) do
    working_dir = Keyword.get(opts, :working_dir, ".")

    %__MODULE__{
      working_dir: working_dir,
      footer: Footer.new(working_dir),
      model_name: OpenRouter.model()
    }
  end

  # ============================================================================
  # Mode predicates
  # ============================================================================

  def normal?(%__MODULE__{mode: :normal}), do: true
  def normal?(%__MODULE__{}), do: false

  def connecting?(%__MODULE__{mode: :connecting}), do: true
  def connecting?(%__MODULE__{}), do: false

  @doc "True while the interface is waiting on the model or on a connection."
  def busy?(%__MODULE__{} = app), do: app.pending or connecting?(app)

  @doc "True when a navigable menu has replaced the prompt."
  def in_menu?(%__MODULE__{mode: {:awaiting_connect_method, _index}}), do: true
  def in_menu?(%__MODULE__{mode: {:awaiting_provider, _index}}), do: true
  def in_menu?(%__MODULE__{}), do: false

  def awaiting_api_key?(%__MODULE__{mode: {:awaiting_api_key, _provider, _browser?}}), do: true
  def awaiting_api_key?(%__MODULE__{}), do: false

  @doc "The prompt's leading marker for the current mode."
  def prompt_prefix(%__MODULE__{} = app) do
    if busy?(app) do
      # A distinct prefix while a request is in flight tells the user their
      # Enter was received, even before the first event streams in.
      "… "
    else
      case app.mode do
        :normal -> "> "
        {:awaiting_api_key, _provider, _browser?} -> "OpenRouter API key: "
        :connecting -> "… "
        # The prompt is hidden behind a menu in the selection states.
        _menu -> ""
      end
    end
  end

  # ============================================================================
  # Submission
  # ============================================================================

  @doc """
  Handles a text submission.

  The slash-menu path goes through `confirm/1` instead.
  """
  def submit(%__MODULE__{} = app) do
    input = app.input
    app = %{app | input: "", show_commands: false, slash_selected: nil}

    case app.mode do
      :normal ->
        submit_normal(app, String.trim(input))

      {:awaiting_api_key, provider, browser?} ->
        submit_api_key(app, provider, browser?, String.trim(input))

      # The selection menus never reach this path; they go through `confirm/1`.
      _other ->
        {app, []}
    end
  end

  defp submit_normal(app, ""), do: {app, []}

  defp submit_normal(app, "/" <> _rest = command), do: submit_slash_command(app, command)

  defp submit_normal(app, prompt) do
    cond do
      # A request is in flight; ignore further submits so the conversation
      # thread stays coherent.
      app.pending ->
        {app, []}

      not app.connected? ->
        {push_error(app, "You are not connected. Run /connect to sign in before sending a prompt."), []}

      true ->
        document =
          app.document
          |> Transcript.push_prompt_echo(app.user_name, prompt)
          |> Transcript.push_attachments(app.attachments)

        # The attachments belong to the turn being sent, so they are read out
        # before the state is cleared for the next one.
        effect = {:submit_prompt, prompt, images(app.attachments)}
        {%{app | document: document, pending: true, attachments: []}, [effect]}
    end
  end

  # The shape `Condukt.Session` attaches to a user message.
  defp images(attachments) do
    Enum.map(attachments, fn attachment ->
      %{type: :base64, media_type: attachment.media_type, data: attachment.data}
    end)
  end

  # ============================================================================
  # Pasting
  # ============================================================================

  @doc """
  Attaches a clipboard image to the turn being composed.

  The prompt gains a marker rather than the image itself, because a terminal has
  no way to show one inside a line of input. The marker is left in the text on
  submit so the model can tell which image a sentence is talking about when more
  than one is attached.

  Returns the state unchanged, with an error in the transcript, when the image is
  too large to send.
  """
  def attach_image(%__MODULE__{} = app, %{media_type: media_type, bytes: bytes}) do
    cond do
      not supported_image?(media_type) ->
        push_error(app, "Cannot attach #{media_type}: only PNG, JPEG, WebP, and GIF images are supported.")

      byte_size(bytes) > max_image_bytes() ->
        push_error(
          app,
          "That image is #{describe_size(byte_size(bytes))} and the limit is #{describe_size(max_image_bytes())}. " <>
            "Save it to a file and ask me to read it instead."
        )

      true ->
        marker = "[image ##{length(app.attachments) + 1}]"
        attachment = %{media_type: media_type, data: Base.encode64(bytes), marker: marker}
        %{app | attachments: app.attachments ++ [attachment], input: append_to_input(app.input, marker)}
    end
  end

  @doc """
  Inserts pasted text into the prompt.

  Text that is entirely paths to image files is attached instead, because
  dragging a file onto a terminal is how it types that path, and the user
  dragging a screenshot in means the image. This is also the only route to
  attaching one that needs nothing installed and works over SSH, where there is
  no clipboard to read.

  Newlines become spaces: the prompt is a single line, and a multi-line paste
  would otherwise be silently truncated at the first break.
  """
  def insert_text(%__MODULE__{} = app, text) do
    flattened = text |> String.replace(["\r\n", "\n", "\r"], " ") |> String.trim_trailing()

    cond do
      flattened == "" -> app
      images = attachable(flattened) -> Enum.reduce(images, app, &attach_image(&2, &1))
      true -> recompute_show_commands(%{app | input: app.input <> flattened})
    end
  end

  defp attachable(text) do
    case Attachment.from_text(text) do
      {:ok, images} -> images
      :none -> nil
    end
  end

  @doc "Largest clipboard image the interface will attach, in bytes."
  def max_image_bytes, do: 8 * 1024 * 1024

  defp supported_image?(media_type), do: media_type in Clipboard.supported_types()

  defp append_to_input(input, marker) do
    cond do
      input == "" -> marker
      String.ends_with?(input, " ") -> input <> marker
      true -> input <> " " <> marker
    end
  end

  defp describe_size(bytes) when bytes >= 1024 * 1024, do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"
  defp describe_size(bytes), do: "#{div(bytes, 1024)} KB"

  defp submit_slash_command(app, input) do
    case Commands.parse(input) do
      :error -> {push_error(app, "Unknown command: #{input}"), []}
      {:ok, definition, argument} -> run_slash_command(app, definition, argument)
    end
  end

  defp run_slash_command(app, %{kind: :quit}, _argument), do: {%{app | should_exit: true}, [:exit]}

  defp run_slash_command(app, %{kind: :help}, _argument) do
    {push_info(app, Commands.help_text()), []}
  end

  defp run_slash_command(app, %{kind: :connect}, _argument) do
    cond do
      app.connected? -> {push_info(app, "OpenRouter is already connected."), []}
      connecting?(app) -> {push_info(app, "A previous connection attempt is still finishing."), []}
      true -> {enter_connect_method(app), []}
    end
  end

  defp run_slash_command(app, %{kind: :files}, _argument), do: {list_workspace_files(app), []}

  defp run_slash_command(app, %{kind: :read, usage: usage}, "") do
    {push_error(app, "Usage: #{usage}"), []}
  end

  defp run_slash_command(app, %{kind: :read}, path), do: {read_workspace_file(app, path), []}

  defp list_workspace_files(app) do
    case Workspace.files(app.working_dir) do
      {:ok, files} -> %{app | document: app.document ++ Enum.map(files, &Transcript.plain/1)}
      {:error, reason} -> push_error(app, "Could not list files: #{:file.format_error(reason)}")
    end
  end

  defp read_workspace_file(app, path) do
    case Workspace.read(app.working_dir, path) do
      {:ok, contents} -> %{app | document: app.document ++ Enum.map(String.split(contents, "\n"), &Transcript.plain/1)}
      {:error, message} -> push_error(app, message)
    end
  end

  # ============================================================================
  # Connect flow
  # ============================================================================

  @doc "Opens the guided connect flow at the authentication-method menu."
  def enter_connect_method(%__MODULE__{} = app) do
    %{
      app
      | document: app.document ++ [Transcript.blank(), Transcript.plain("Let's connect your account.")],
        mode: {:awaiting_connect_method, 0}
    }
  end

  defp submit_api_key(app, _provider, _browser?, "") do
    {push_error(app, "API key cannot be empty. Press Esc to cancel."), []}
  end

  defp submit_api_key(app, provider, _browser?, key) do
    if openrouter?(provider) do
      {%{app | mode: :connecting}, [{:connect_with_key, key}]}
    else
      {%{push_error(app, "Unknown provider: #{provider}") | mode: :normal}, []}
    end
  end

  @doc """
  Moves into API-key input.

  When `open_browser?` is set, the host browser is pointed at the provider's key
  page so the user can create or copy a key without leaving the agent.
  """
  def begin_api_key_input(%__MODULE__{} = app, provider, open_browser?) do
    {app, effects} =
      if open_browser? and openrouter?(provider) do
        url = OpenRouter.keys_url()

        document =
          app.document ++
            [
              Transcript.blank(),
              Transcript.plain("Opening #{url} in your browser. Create or copy a key there, then paste it below.")
            ]

        {%{app | document: document}, [{:open_browser, url}]}
      else
        {app, []}
      end

    app = %{app | document: app.document ++ [Transcript.blank()]}
    app = push_info(app, "Paste your API key below. Press Esc to cancel.")
    {%{app | mode: {:awaiting_api_key, provider, open_browser?}}, effects}
  end

  @doc """
  Starts browser sign-in for a provider.

  The host performs the sign-in and reports back through `login_started/2` or
  `login_failed/2`.
  """
  def begin_oauth_flow(%__MODULE__{} = app, provider) do
    if openrouter?(provider) do
      {app, [{:start_oauth, provider}]}
    else
      {%{push_error(app, "Unknown provider: #{provider}") | mode: :normal}, []}
    end
  end

  @doc "Records that a browser sign-in is under way."
  def login_started(%__MODULE__{} = app, authorize_url) do
    app = push_info(app, "Complete sign-in in your browser. Press Esc to cancel.")
    {%{app | mode: :connecting}, [{:open_browser, authorize_url}]}
  end

  @doc "Records that a browser sign-in could not be started."
  def login_failed(%__MODULE__{} = app, message) do
    %{push_error(app, "OpenRouter sign-in failed: #{message}") | mode: :normal}
  end

  @doc """
  Cancels an in-flight connection attempt.

  Returns `{app, effects}` with a `{:cancel_connection}` effect, or `:noop` when
  nothing was in flight, so the caller can fall through to its next handler.
  """
  def cancel_connection(%__MODULE__{} = app) do
    if connecting?(app) do
      {%{push_info(app, "Connection cancelled.") | mode: :normal}, [:cancel_connection]}
    else
      :noop
    end
  end

  @doc "Applies the outcome of a connection attempt."
  def connection_result(%__MODULE__{} = app, :ok) do
    app = %{app | connected?: true, mode: :normal}
    %{app | document: app.document ++ [Transcript.styled("OpenRouter connected.", Theme.accent_text())]}
  end

  def connection_result(%__MODULE__{} = app, {:error, message}) do
    app
    |> push_error(message)
    |> push_info("Run /connect to try again.")
    |> Map.put(:mode, :normal)
  end

  defp openrouter?(provider), do: String.downcase(provider) == "openrouter"

  # ============================================================================
  # Transcript
  # ============================================================================

  @doc "Appends a plain informational line."
  def push_info(%__MODULE__{} = app, message), do: %{app | document: Transcript.push_info(app.document, message)}

  @doc "Appends a titled error block."
  def push_error(%__MODULE__{} = app, message), do: %{app | document: Transcript.push_error(app.document, message)}

  @doc "Appends a completed model message."
  def push_model_message(%__MODULE__{} = app, text) do
    if String.trim(text) == "" do
      app
    else
      %{app | document: Transcript.push_model_message(app.document, app.model_name, text)}
    end
  end

  @doc "Appends a tool invocation."
  def push_tool_call(%__MODULE__{} = app, name, arguments) do
    document = Transcript.begin_activity_group(app.document) ++ [Transcript.tool_call_line(name, arguments)]
    %{app | document: document}
  end

  @doc "Appends a tool result, keeping it attached to its invocation."
  def push_tool_result(%__MODULE__{} = app, name, output) do
    %{app | document: app.document ++ [Transcript.tool_result_line(name, output)]}
  end

  # ============================================================================
  # Presentation
  # ============================================================================

  def document_lines(%__MODULE__{} = app), do: app.document

  @doc "Vertical scroll offset for a viewport of `viewport_height` rows."
  def document_scroll(%__MODULE__{} = app, viewport_height) do
    max_scroll = max(length(app.document) - viewport_height, 0)
    max(max_scroll - app.document_scroll_from_bottom, 0)
  end

  def scroll_document_up(%__MODULE__{} = app) do
    %{app | document_scroll_from_bottom: app.document_scroll_from_bottom + @scroll_step}
  end

  def scroll_document_down(%__MODULE__{} = app) do
    %{app | document_scroll_from_bottom: max(app.document_scroll_from_bottom - @scroll_step, 0)}
  end

  @doc "True when the slash menu should be drawn."
  def show_commands?(%__MODULE__{} = app), do: app.show_commands and normal?(app)

  @doc """
  Recomputes slash-menu visibility and resets its selection.

  Called after every input change so the menu hides as soon as the typed query
  stops matching a command.
  """
  def recompute_show_commands(%__MODULE__{} = app) do
    showing? =
      normal?(app) and String.starts_with?(app.input, "/") and
        Commands.filter(slash_query(app)) != []

    %{app | show_commands: showing?, slash_selected: if(showing?, do: 0)}
  end

  defp slash_query(%__MODULE__{input: input}), do: String.trim_leading(input, "/")

  @doc """
  Renders the slash-command menu.

  Every row uses the accent colour; the selected row is bolded and marked with
  an arrow, so the arrow is the only thing that moves as the selection changes.
  """
  def slash_menu_lines(%__MODULE__{} = app) do
    app
    |> slash_query()
    |> Commands.filter()
    |> Enum.with_index()
    |> Enum.map(fn {command, index} ->
      selected? = app.slash_selected == index

      line =
        RichText.new()
        |> RichText.push_text(if selected?, do: "→ ", else: "  ")
        |> RichText.push_text("/")
        |> RichText.push_command(String.pad_trailing(command.name, 10))
        |> RichText.push_text(command.description)
        |> RichText.to_line()

      style = if selected?, do: Theme.selected(), else: Theme.accent_text()
      %{line | style: style}
    end)
  end

  @doc "Rows the active selection menu needs, including its borders."
  def menu_height(%__MODULE__{} = app) do
    case menu_options(app) do
      # 1 header + 1 spacer + N options + 1 spacer + 1 hint + 2 borders
      nil -> 0
      options -> length(options) + 6
    end
  end

  @doc "Renders the active selection menu."
  def menu_lines(%__MODULE__{} = app) do
    case {menu_question(app), menu_options(app)} do
      {nil, _options} ->
        []

      {_question, nil} ->
        []

      {question, options} ->
        header = [
          Transcript.styled(question, %Style{modifiers: [:bold]}),
          Transcript.blank()
        ]

        hint = [
          Transcript.blank(),
          Transcript.styled("↑↓ navigate   enter select   escape/ctrl+c cancel", Theme.muted_text())
        ]

        header ++ menu_rows(options, menu_selection(app)) ++ hint
    end
  end

  defp menu_rows(options, selected) do
    options
    |> Enum.with_index()
    |> Enum.map(fn {option, index} -> menu_row(option, index == selected) end)
  end

  defp menu_row(option, selected?) do
    prefix = if selected?, do: "→ ", else: "  "
    style = if selected?, do: Theme.selected(), else: %Style{}
    Transcript.styled(prefix <> option.description, style)
  end

  defp menu_question(%__MODULE__{mode: {:awaiting_connect_method, _index}}), do: "Select authentication method:"
  defp menu_question(%__MODULE__{mode: {:awaiting_provider, _index}}), do: "Choose a provider:"
  defp menu_question(%__MODULE__{}), do: nil

  defp menu_options(%__MODULE__{mode: {:awaiting_connect_method, _index}}), do: @connect_methods
  defp menu_options(%__MODULE__{mode: {:awaiting_provider, _index}}), do: @providers
  defp menu_options(%__MODULE__{}), do: nil

  defp menu_selection(%__MODULE__{mode: {:awaiting_connect_method, index}}), do: index
  defp menu_selection(%__MODULE__{mode: {:awaiting_provider, index}}), do: index
  defp menu_selection(%__MODULE__{}), do: 0

  # ============================================================================
  # Navigation
  # ============================================================================

  @doc "Moves the active menu's selection up. A no-op when nothing is navigable."
  def select_up(%__MODULE__{} = app), do: move_selection(app, -1)

  @doc "Moves the active menu's selection down. A no-op when nothing is navigable."
  def select_down(%__MODULE__{} = app), do: move_selection(app, 1)

  defp move_selection(%__MODULE__{mode: {menu, index}} = app, step)
       when menu in [:awaiting_connect_method, :awaiting_provider] do
    count = length(menu_options(app))
    %{app | mode: {menu, Integer.mod(index + step, count)}}
  end

  defp move_selection(%__MODULE__{mode: :normal} = app, step) do
    if app.show_commands, do: move_slash_selection(app, step), else: app
  end

  defp move_selection(%__MODULE__{} = app, _step), do: app

  defp move_slash_selection(app, step) do
    case length(Commands.filter(slash_query(app))) do
      0 -> %{app | slash_selected: nil}
      count -> %{app | slash_selected: Integer.mod((app.slash_selected || 0) + step, count)}
    end
  end

  @doc """
  Confirms the current selection.

  In a connect-flow menu this advances the state machine; in the slash menu it
  runs the highlighted command; otherwise the typed input is submitted.
  """
  def confirm(%__MODULE__{mode: {menu, _index}} = app) when menu in [:awaiting_connect_method, :awaiting_provider] do
    confirm_menu(app)
  end

  def confirm(%__MODULE__{mode: :connecting} = app), do: {app, []}

  def confirm(%__MODULE__{mode: :normal} = app) do
    if app.show_commands and app.slash_selected, do: confirm_slash_selection(app), else: submit(app)
  end

  def confirm(%__MODULE__{} = app), do: submit(app)

  defp confirm_menu(%__MODULE__{mode: {:awaiting_connect_method, index}} = app) do
    case Enum.at(@connect_methods, index) do
      %{value: "account"} -> {%{app | mode: {:awaiting_provider, 0}}, []}
      %{value: "api-key"} -> begin_api_key_input(app, "openrouter", false)
      _other -> {app, []}
    end
  end

  defp confirm_menu(%__MODULE__{mode: {:awaiting_provider, index}} = app) do
    case Enum.at(@providers, index) do
      %{value: provider} -> begin_oauth_flow(app, provider)
      _other -> {app, []}
    end
  end

  defp confirm_slash_selection(app) do
    commands = Commands.filter(slash_query(app))

    case Enum.at(commands, app.slash_selected) do
      nil ->
        {app, []}

      command ->
        %{app | input: "/" <> command.name, slash_selected: nil, show_commands: false}
        |> submit()
    end
  end

  defp system_user_name do
    System.get_env("USER") || System.get_env("USERNAME") || "You"
  end
end
