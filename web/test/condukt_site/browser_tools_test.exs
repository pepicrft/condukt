defmodule ConduktSite.BrowserToolsTest do
  use ExUnit.Case, async: true

  alias ConduktSite.BrowserTools

  defp declaration(overrides \\ %{}) do
    Map.merge(
      %{
        "name" => "list_repository_directory",
        "description" => "List a directory.",
        "parameters" => %{"type" => "object", "properties" => %{}}
      },
      overrides
    )
  end

  describe "building tools from what the page declares" do
    test "a declaration becomes a callable tool" do
      [tool] = BrowserTools.build([declaration()], self())

      assert tool.name == "list_repository_directory"
      assert tool.description == "List a directory."
      assert is_function(tool.call, 2)
    end

    test "declarations are capped, so a page cannot flood the model's tool list" do
      declarations =
        for index <- 1..(BrowserTools.max_tools() * 3),
            do: declaration(%{"name" => "tool_#{index}"})

      assert length(BrowserTools.build(declarations, self())) == BrowserTools.max_tools()
    end

    test "one malformed declaration costs that tool and not the rest" do
      declarations = [
        declaration(%{"name" => "has a space"}),
        %{"name" => "no_description"},
        declaration(%{"parameters" => "not an object"}),
        declaration(%{"name" => "read_repository_file"})
      ]

      assert [%{name: "read_repository_file"}] = BrowserTools.build(declarations, self())
    end

    test "an oversized description is refused rather than truncated" do
      assert [] =
               BrowserTools.build(
                 [declaration(%{"description" => String.duplicate("x", 8_000)})],
                 self()
               )
    end

    test "anything that is not a list of declarations yields no tools" do
      assert BrowserTools.build(%{"tools" => []}, self()) == []
      assert BrowserTools.build([], self()) == []
    end
  end

  # The session never calls `call/3` itself. It executes the tool struct, so
  # that is the path worth proving end to end.
  describe "the path the session actually takes" do
    test "executing the built tool reaches the page and returns its answer" do
      page = self()
      [tool] = BrowserTools.build([declaration()], page)

      task = Task.async(fn -> Condukt.Tool.execute(tool, %{"path" => "lib"}, %{}) end)

      assert_receive {:browser_tool, caller, ref, "list_repository_directory", %{"path" => "lib"}}
      send(caller, {:browser_tool_result, ref, {:ok, %{"entries" => []}}})

      assert Task.await(task) == {:ok, %{"entries" => []}}
    end
  end

  describe "calling into the page" do
    test "the invocation is sent to the page and the answer is returned" do
      page = self()

      task =
        Task.async(fn ->
          BrowserTools.call(page, "read_repository_file", %{"path" => "mix.exs"})
        end)

      assert_receive {:browser_tool, caller, ref, "read_repository_file", %{"path" => "mix.exs"}}
      send(caller, {:browser_tool_result, ref, {:ok, %{"content" => "defmodule"}}})

      assert Task.await(task) == {:ok, %{"content" => "defmodule"}}
    end

    test "a tool that fails in the browser comes back as an error, not a crash" do
      page = self()
      task = Task.async(fn -> BrowserTools.call(page, "read_repository_file", %{}) end)

      assert_receive {:browser_tool, caller, ref, _name, _args}
      send(caller, {:browser_tool_result, ref, {:error, "GitHub returned status 404"}})

      assert Task.await(task) == {:error, "GitHub returned status 404"}
    end

    # A closed tab must end the tool immediately. Waiting out the timeout would
    # hold the turn open for half a minute for an answer that cannot arrive.
    test "a page that goes away ends the call rather than waiting for the timeout" do
      page = spawn(fn -> Process.sleep(:infinity) end)
      task = Task.async(fn -> BrowserTools.call(page, "read_repository_file", %{}) end)

      Process.exit(page, :kill)

      assert {:error, message} = Task.await(task, 1_000)
      assert message =~ "closed before"
    end

    test "the timeout is shorter than the session's own tool timeout" do
      assert BrowserTools.call_timeout() < 300_000
    end
  end
end
