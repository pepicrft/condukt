defmodule Condukt.CLI.AppTest do
  use ExUnit.Case, async: true

  alias Condukt.CLI.App

  defp document_text(app) do
    Enum.map_join(app.document, "\n", fn line -> Enum.map_join(line.spans, & &1.content) end)
  end

  defp with_input(app, input), do: App.recompute_show_commands(%{app | input: input})

  describe "launch" do
    test "an unconnected launch tells the user how to connect" do
      app = App.new(connected?: false)
      assert document_text(app) =~ "/connect"
    end

    test "a connected launch skips the hint" do
      app = App.new(connected?: true)
      refute document_text(app) =~ "/connect"
    end

    test "warnings from restoring a credential are shown as errors" do
      app = App.new(connected?: false, warnings: ["Could not restore the saved connection"])
      assert document_text(app) =~ "Error"
      assert document_text(app) =~ "Could not restore the saved connection"
    end
  end

  describe "prompts" do
    test "submitting without a connection explains what to do" do
      {app, effects} = App.empty() |> with_input("explain this project") |> App.submit()

      assert effects == []
      assert document_text(app) =~ "You are not connected"
    end

    test "a connected submit echoes the prompt and asks the host to run it" do
      {app, effects} =
        App.empty()
        |> Map.put(:connected?, true)
        |> with_input("explain this project")
        |> App.submit()

      assert effects == [{:submit_prompt, "explain this project", []}]
      assert app.pending
      assert document_text(app) =~ "explain this project"
    end

    test "a submit while a request is in flight is ignored" do
      app = %{App.empty() | connected?: true, pending: true}
      {app, effects} = app |> with_input("another one") |> App.submit()

      assert effects == []
      refute document_text(app) =~ "another one"
    end

    test "an empty submit does nothing" do
      {app, effects} = App.empty() |> with_input("   ") |> App.submit()
      assert effects == []
      assert app.document == []
    end
  end

  describe "slash commands" do
    test "quit asks the host to leave" do
      {app, effects} = App.empty() |> with_input("/quit") |> App.submit()
      assert app.should_exit
      assert effects == [:exit]
    end

    test "help prints the catalogue" do
      {app, _effects} = App.empty() |> with_input("/help") |> App.submit()
      assert document_text(app) =~ "/connect"
      assert document_text(app) =~ "/read <path>"
    end

    test "an unknown command is reported" do
      {app, _effects} = App.empty() |> with_input("/teleport") |> App.submit()
      assert document_text(app) =~ "Unknown command: /teleport"
    end

    test "read without a path shows its usage" do
      {app, _effects} = App.empty() |> with_input("/read") |> App.submit()
      assert document_text(app) =~ "Usage: /read <path>"
    end

    test "connect opens the guided flow" do
      {app, _effects} = App.empty() |> with_input("/connect") |> App.submit()
      assert {:awaiting_connect_method, 0} = app.mode
      assert document_text(app) =~ "Let's connect your account."
    end

    test "connect says so when already connected" do
      app = %{App.empty() | connected?: true}
      {app, _effects} = app |> with_input("/connect") |> App.submit()
      assert document_text(app) =~ "already connected"
      assert App.normal?(app)
    end

    test "files lists the workspace root" do
      root = temporary_directory()
      File.write!(Path.join(root, "one.txt"), "1")
      File.write!(Path.join(root, "two.txt"), "2")

      {app, _effects} =
        App.empty(working_dir: root) |> with_input("/files") |> App.submit()

      assert document_text(app) =~ "one.txt"
      assert document_text(app) =~ "two.txt"
    end

    test "read shows a workspace file" do
      root = temporary_directory()
      File.write!(Path.join(root, "hello.txt"), "hello, world")

      {app, _effects} =
        App.empty(working_dir: root) |> with_input("/read hello.txt") |> App.submit()

      assert document_text(app) =~ "hello, world"
    end

    test "reading a missing file reports the failure" do
      {app, _effects} =
        App.empty(working_dir: temporary_directory())
        |> with_input("/read nope.txt")
        |> App.submit()

      assert document_text(app) =~ "could not read"
    end
  end

  describe "attachments" do
    defp png(bytes \\ 32), do: %{media_type: "image/png", bytes: :binary.copy(<<137, 80, 78, 71>>, bytes)}

    test "an attached image gets a marker in the prompt" do
      app = App.attach_image(App.empty(), png())

      assert app.input == "[image #1]"
      assert [%{media_type: "image/png", marker: "[image #1]"}] = app.attachments
    end

    test "the image is carried as base64" do
      app = App.attach_image(App.empty(), %{media_type: "image/png", bytes: "raw bytes"})

      assert [%{data: data}] = app.attachments
      assert Base.decode64!(data) == "raw bytes"
    end

    test "markers are numbered and spaced away from what is already typed" do
      app =
        %{App.empty() | input: "what is wrong here?"}
        |> App.attach_image(png())
        |> App.attach_image(png())

      assert app.input == "what is wrong here? [image #1] [image #2]"
      assert length(app.attachments) == 2
    end

    test "submitting sends the images and clears them" do
      {app, effects} =
        %{App.empty() | connected?: true}
        |> App.attach_image(%{media_type: "image/png", bytes: "one"})
        |> App.submit()

      assert [{:submit_prompt, "[image #1]", [image]}] = effects
      assert image == %{type: :base64, media_type: "image/png", data: Base.encode64("one")}
      assert app.attachments == []
    end

    test "the transcript records what went with the turn" do
      {app, _effects} =
        %{App.empty() | connected?: true, input: "look"}
        |> App.attach_image(png())
        |> App.submit()

      assert document_text(app) =~ "attached [image #1]"
    end

    test "a turn with no attachment says nothing about them" do
      {app, effects} = %{App.empty() | connected?: true, input: "look"} |> App.submit()

      assert [{:submit_prompt, "look", []}] = effects
      refute document_text(app) =~ "attached"
    end

    test "an unsupported image type is refused with a reason" do
      app = App.attach_image(App.empty(), %{media_type: "image/tiff", bytes: "x"})

      assert app.attachments == []
      assert document_text(app) =~ "only PNG, JPEG, WebP, and GIF"
    end

    # Base64 inflates by a third on the way to the provider, and a rejected
    # request would surface as an opaque provider error rather than something
    # the user can act on.
    test "an image beyond the limit is refused with its size" do
      oversized = %{media_type: "image/png", bytes: :binary.copy("x", App.max_image_bytes() + 1)}
      app = App.attach_image(App.empty(), oversized)

      assert app.attachments == []
      assert document_text(app) =~ "8.0 MB"
    end
  end

  describe "pasted text" do
    test "is appended to the prompt" do
      app = App.insert_text(%{App.empty() | input: "see "}, "this file")

      assert app.input == "see this file"
    end

    # The prompt is one line, so a multi-line paste would otherwise be cut at
    # the first break with no sign that anything was lost.
    test "arrives flattened onto the single prompt line" do
      app = App.insert_text(App.empty(), "first\nsecond\r\nthird")

      assert app.input == "first second third"
    end

    test "opens the slash menu when it starts a command" do
      app = App.insert_text(App.empty(), "/conn")

      assert App.show_commands?(app)
    end

    # Dragging a file onto a terminal makes it type that file's path. This is
    # the route to attaching an image that needs nothing installed, and the only
    # one that works over SSH, where there is no clipboard at all.
    test "a dragged image file is attached rather than typed" do
      root = temporary_directory()
      path = Path.join(root, "shot.png")
      File.write!(path, <<137, 80, 78, 71, 13, 10, 26, 10>>)

      app = App.insert_text(App.empty(), path)

      assert app.input == "[image #1]"
      assert [%{media_type: "image/png"}] = app.attachments
    end

    test "a sentence that merely mentions a path stays text" do
      root = temporary_directory()
      path = Path.join(root, "shot.png")
      File.write!(path, <<137, 80, 78, 71, 13, 10, 26, 10>>)

      app = App.insert_text(App.empty(), "look at #{path}")

      assert app.input == "look at #{path}"
      assert app.attachments == []
    end

    test "empty text leaves the prompt alone" do
      assert App.insert_text(%{App.empty() | input: "kept"}, "  \n ").input == "kept"
    end
  end

  describe "the slash menu" do
    test "typing a slash opens the menu with the first entry highlighted" do
      app = App.empty() |> with_input("/")
      assert App.show_commands?(app)
      assert app.slash_selected == 0
    end

    test "a query nothing matches closes the menu" do
      app = App.empty() |> with_input("/zzzz")
      refute App.show_commands?(app)
      assert app.slash_selected == nil
    end

    test "the selection wraps in both directions" do
      app = App.empty() |> with_input("/")
      count = length(App.slash_menu_lines(app))

      assert App.select_down(app).slash_selected == 1
      assert App.select_up(app).slash_selected == count - 1
    end

    test "confirming runs the highlighted command" do
      app = App.empty() |> with_input("/qui")
      {app, effects} = App.confirm(app)

      assert app.should_exit
      assert effects == [:exit]
    end

    test "the highlighted row is the only bold one" do
      app = App.empty() |> with_input("/")
      [first, second | _rest] = App.slash_menu_lines(app)

      assert :bold in first.style.modifiers
      refute :bold in second.style.modifiers
    end
  end

  describe "the connect flow" do
    test "choosing an account moves to the provider menu" do
      app = %{App.empty() | mode: {:awaiting_connect_method, 0}}
      {app, effects} = App.confirm(app)

      assert {:awaiting_provider, 0} = app.mode
      assert effects == []
    end

    test "choosing a key moves to key entry without opening a browser" do
      app = %{App.empty() | mode: {:awaiting_connect_method, 1}}
      {app, effects} = App.confirm(app)

      assert {:awaiting_api_key, "openrouter", false} = app.mode
      assert effects == []
      assert document_text(app) =~ "Paste your API key below"
    end

    test "choosing a provider asks the host to start browser sign-in" do
      app = %{App.empty() | mode: {:awaiting_provider, 0}}
      {_app, effects} = App.confirm(app)

      assert effects == [{:start_oauth, "openrouter"}]
    end

    test "starting sign-in opens the browser and marks the interface busy" do
      {app, effects} = App.login_started(App.empty(), "https://openrouter.ai/auth?x=1")

      assert App.connecting?(app)
      assert effects == [{:open_browser, "https://openrouter.ai/auth?x=1"}]
      assert document_text(app) =~ "Complete sign-in in your browser"
    end

    test "a failed sign-in returns to normal mode with an explanation" do
      app = App.login_failed(App.empty(), "no port available")

      assert App.normal?(app)
      assert document_text(app) =~ "OpenRouter sign-in failed: no port available"
    end

    test "an empty key is rejected without leaving key entry" do
      app = %{App.empty() | mode: {:awaiting_api_key, "openrouter", false}, input: "  "}
      {app, effects} = App.submit(app)

      assert {:awaiting_api_key, "openrouter", false} = app.mode
      assert effects == []
      assert document_text(app) =~ "API key cannot be empty"
    end

    test "a key submission asks the host to validate it" do
      app = %{App.empty() | mode: {:awaiting_api_key, "openrouter", false}, input: "sk-or-v1-test"}
      {app, effects} = App.submit(app)

      assert App.connecting?(app)
      assert effects == [{:connect_with_key, "sk-or-v1-test"}]
    end

    test "an unknown provider is rejected" do
      app = %{App.empty() | mode: {:awaiting_api_key, "acme", false}, input: "key"}
      {app, effects} = App.submit(app)

      assert App.normal?(app)
      assert effects == []
      assert document_text(app) =~ "Unknown provider: acme"
    end

    test "opening key entry with a browser points at the provider's key page" do
      {app, effects} = App.begin_api_key_input(App.empty(), "openrouter", true)

      assert effects == [{:open_browser, "https://openrouter.ai/keys"}]
      assert document_text(app) =~ "Opening https://openrouter.ai/keys"
    end

    test "a successful connection is recorded" do
      app = App.connection_result(%{App.empty() | mode: :connecting}, :ok)

      assert app.connected?
      assert App.normal?(app)
      assert document_text(app) =~ "OpenRouter connected."
    end

    test "a failed connection explains how to retry" do
      app = App.connection_result(%{App.empty() | mode: :connecting}, {:error, "key rejected"})

      refute app.connected?
      assert App.normal?(app)
      assert document_text(app) =~ "key rejected"
      assert document_text(app) =~ "Run /connect to try again."
    end

    test "cancelling only applies while a connection is in flight" do
      assert App.cancel_connection(App.empty()) == :noop

      {app, effects} = App.cancel_connection(%{App.empty() | mode: :connecting})
      assert App.normal?(app)
      assert effects == [:cancel_connection]
      assert document_text(app) =~ "Connection cancelled."
    end

    test "menu navigation wraps around the options" do
      app = %{App.empty() | mode: {:awaiting_connect_method, 0}}

      assert App.select_down(app).mode == {:awaiting_connect_method, 1}
      assert App.select_up(app).mode == {:awaiting_connect_method, 1}
    end
  end

  describe "presentation" do
    test "the prompt marker follows the mode" do
      assert App.prompt_prefix(App.empty()) == "> "

      assert App.prompt_prefix(%{App.empty() | mode: {:awaiting_api_key, "openrouter", false}}) ==
               "OpenRouter API key: "

      assert App.prompt_prefix(%{App.empty() | mode: :connecting}) == "… "
      assert App.prompt_prefix(%{App.empty() | pending: true}) == "… "
      assert App.prompt_prefix(%{App.empty() | mode: {:awaiting_provider, 0}}) == ""
    end

    test "the menu reserves a row for each option plus its chrome" do
      app = %{App.empty() | mode: {:awaiting_connect_method, 0}}
      assert App.menu_height(app) == length(App.connect_methods()) + 6
      assert App.menu_height(App.empty()) == 0
    end

    test "the menu marks its selection with an arrow" do
      app = %{App.empty() | mode: {:awaiting_connect_method, 1}}
      text = Enum.map(App.menu_lines(app), fn line -> Enum.map_join(line.spans, & &1.content) end)

      assert Enum.any?(text, &String.starts_with?(&1, "→ Sign in with an API key"))
      assert Enum.any?(text, &String.starts_with?(&1, "  Sign in with an account"))
    end

    test "the transcript follows the newest entry until it is scrolled" do
      app = %{App.empty() | document: Enum.map(1..10, fn index -> line("row #{index}") end)}

      assert App.document_scroll(app, 2) == 8
      assert app |> App.scroll_document_up() |> App.document_scroll(2) == 5
      assert app |> App.scroll_document_up() |> App.scroll_document_down() |> App.document_scroll(2) == 8
    end

    test "scrolling down stops at the newest entry" do
      app = App.empty() |> App.scroll_document_down() |> App.scroll_document_down()
      assert app.document_scroll_from_bottom == 0
    end
  end

  describe "streamed activity" do
    test "a model message becomes one titled block" do
      app = App.push_model_message(App.empty(), "first\nsecond")
      text = document_text(app)

      assert text =~ "▌ " <> App.empty().model_name
      assert text =~ "first"
      assert text =~ "second"
    end

    test "empty model text is dropped" do
      assert App.push_model_message(App.empty(), "  \n ").document == []
    end

    test "a tool call and its result stay together" do
      app =
        App.empty()
        |> App.push_tool_call("bash", %{"command" => "ls"})
        |> App.push_tool_result("bash", "one.txt\ntwo.txt")

      text = document_text(app)
      assert text =~ "tool bash"
      assert text =~ ~s({"command":"ls"})
      assert text =~ "one.txt"
      refute text =~ "two.txt"
    end

    test "an error is its own titled block" do
      app = App.push_error(App.empty(), "Request failed: timeout")
      assert document_text(app) =~ "Error"
      assert document_text(app) =~ "Request failed: timeout"
    end
  end

  defp line(content) do
    %ExRatatui.Text.Line{spans: [%ExRatatui.Text.Span{content: content}]}
  end

  defp temporary_directory do
    directory = Path.join(System.tmp_dir!(), "condukt-app-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    on_exit_delete(directory)
    directory
  end

  defp on_exit_delete(directory) do
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf(directory) end)
  end
end
