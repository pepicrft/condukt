defmodule Condukt.AnonymousRunTest do
  use ExUnit.Case, async: false
  use Mimic

  alias ReqLLM.Message
  alias ReqLLM.Message.ContentPart
  alias ReqLLM.Response
  alias ReqLLM.ToolCall

  setup :set_mimic_from_context
  setup :verify_on_exit!

  describe "Condukt.tool/1" do
    test "builds an inline tool struct with the required fields" do
      tool =
        Condukt.tool(
          name: "echo",
          description: "Echoes the input text.",
          parameters: %{type: "object", properties: %{text: %{type: "string"}}, required: ["text"]},
          call: fn %{"text" => text}, _ctx -> {:ok, text} end
        )

      assert %Condukt.Tool.Inline{name: "echo"} = tool
      assert tool.description =~ "Echoes"
      assert tool.parameters.required == ["text"]
      assert is_function(tool.call, 2)
    end

    test "raises a clear error when a required field is missing" do
      assert_raise KeyError, fn ->
        Condukt.tool(name: "no-call")
      end
    end
  end

  describe "Condukt.Tool dispatch on inline tools" do
    test "Tool.to_spec/1 returns the inline fields" do
      tool =
        Condukt.tool(
          name: "n",
          description: "d",
          parameters: %{type: "object", properties: %{}},
          call: fn _, _ -> {:ok, "ok"} end
        )

      assert Condukt.Tool.to_spec(tool) == %{
               name: "n",
               description: "d",
               parameters: %{type: "object", properties: %{}}
             }
    end

    test "Tool.execute/3 invokes the inline callback" do
      tool =
        Condukt.tool(
          name: "double",
          description: "doubles the value",
          parameters: %{type: "object", properties: %{x: %{type: "integer"}}, required: ["x"]},
          call: fn %{"x" => x}, _ctx -> {:ok, x * 2} end
        )

      assert {:ok, 6} = Condukt.Tool.execute(tool, %{"x" => 3}, %{agent: self(), sandbox: nil, cwd: "."})
    end

    test "Tool.execute/3 wraps inline callback exceptions" do
      tool =
        Condukt.tool(
          name: "boom",
          description: "raises",
          parameters: %{type: "object", properties: %{}},
          call: fn _, _ -> raise "kaboom" end
        )

      assert {:error, "kaboom"} = Condukt.Tool.execute(tool, %{}, %{agent: self(), sandbox: nil, cwd: "."})
    end

    test "Tool.name/1 returns the inline name" do
      tool =
        Condukt.tool(
          name: "named",
          description: "d",
          parameters: %{type: "object", properties: %{}},
          call: fn _, _ -> {:ok, ""} end
        )

      assert Condukt.Tool.name(tool) == "named"
    end
  end

  describe "Condukt.run/2 free-form (no input, no output)" do
    test "runs an anonymous session and returns the assistant text" do
      ReqLLM
      |> expect(:generate_text, fn _model, _context, _opts ->
        message = %Message{
          role: :assistant,
          content: [ContentPart.text("hello back")],
          tool_calls: nil
        }

        {:ok, response(message, :stop)}
      end)

      assert {:ok, "hello back"} =
               Condukt.run("hello",
                 model: "anthropic:claude-sonnet-4-20250514",
                 system_prompt: "be terse"
               )
    end

    test "calls inline tools the model invokes" do
      pid = self()

      tool =
        Condukt.tool(
          name: "ping",
          description: "Sends a ping",
          parameters: %{type: "object", properties: %{msg: %{type: "string"}}, required: ["msg"]},
          call: fn %{"msg" => msg}, _ctx ->
            send(pid, {:tool_called, msg})
            {:ok, "pong"}
          end
        )

      ReqLLM
      |> expect(:generate_text, fn _model, _context, opts ->
        # Verify the inline tool was registered with ReqLLM under its inline name.
        assert Enum.any?(opts[:tools], &(&1.name == "ping"))

        tool_call = ToolCall.new("call_1", "ping", JSON.encode!(%{"msg" => "hi"}))

        {:ok, response(%Message{role: :assistant, content: [], tool_calls: [tool_call]}, :tool_calls)}
      end)
      |> expect(:generate_text, fn _model, _context, _opts ->
        {:ok, response(%Message{role: :assistant, content: [ContentPart.text("done")], tool_calls: nil}, :stop)}
      end)

      assert {:ok, "done"} = Condukt.run("ping me", tools: [tool])
      assert_receive {:tool_called, "hi"}
    end
  end

  describe "Condukt.run/2 with :input (no output)" do
    test "returns text and validates input when :input_schema is given" do
      ReqLLM
      |> expect(:generate_text, fn _model, context, _opts ->
        # The encoded args should appear as the user message.
        user_message = Enum.find(context.messages, &(&1.role == :user))
        assert user_message
        text = Enum.map_join(user_message.content, "", & &1.text)
        assert text =~ "tuist/condukt"

        {:ok, response(%Message{role: :assistant, content: [ContentPart.text("ack")], tool_calls: nil}, :stop)}
      end)

      assert {:ok, "ack"} =
               Condukt.run("Run the task with these args.",
                 input: %{repo: "tuist/condukt", pr_number: 42},
                 input_schema: %{
                   type: "object",
                   properties: %{repo: %{type: "string"}, pr_number: %{type: "integer"}},
                   required: ["repo", "pr_number"]
                 }
               )
    end

    test "rejects input that does not match :input_schema" do
      assert {:error, {:invalid_input, %JSV.ValidationError{}}} =
               Condukt.run("task",
                 input: %{repo: "tuist/condukt"},
                 input_schema: %{
                   type: "object",
                   properties: %{repo: %{type: "string"}, pr_number: %{type: "integer"}},
                   required: ["repo", "pr_number"]
                 }
               )
    end

    test "rejects non-map input" do
      assert {:error, {:invalid_input, _}} = Condukt.run("task", input: "not a map")
    end
  end

  describe "Condukt.run/2 structured (with :output)" do
    @output_schema %{
      type: "object",
      properties: %{
        verdict: %{type: "string", enum: ["approve", "request_changes"]},
        summary: %{type: "string"}
      },
      required: ["verdict", "summary"]
    }

    test "captures submit_result, validates output, returns atomized map" do
      submitted = %{"verdict" => "approve", "summary" => "Looks good."}

      ReqLLM
      |> expect(:generate_text, fn _model, _context, opts ->
        assert Enum.any?(opts[:tools], &(&1.name == "submit_result"))

        tool_call = ToolCall.new("call_1", "submit_result", JSON.encode!(submitted))
        {:ok, response(%Message{role: :assistant, content: [], tool_calls: [tool_call]}, :tool_calls)}
      end)
      |> expect(:generate_text, fn _model, _context, _opts ->
        {:ok, response(%Message{role: :assistant, content: [ContentPart.text("done")], tool_calls: nil}, :stop)}
      end)

      assert {:ok, %{verdict: "approve", summary: "Looks good."}} =
               Condukt.run("Decide a verdict.",
                 input: %{repo: "x", pr_number: 1},
                 output: @output_schema
               )
    end

    test "appends submit_result alongside user-provided tools" do
      submitted = %{"verdict" => "approve", "summary" => "ok"}
      caller = self()

      passthrough =
        Condukt.tool(
          name: "passthrough",
          description: "no-op",
          parameters: %{type: "object", properties: %{}},
          call: fn _, _ -> {:ok, "noop"} end
        )

      ReqLLM
      |> expect(:generate_text, fn _model, _context, opts ->
        send(caller, {:tools_seen, Enum.map(opts[:tools], & &1.name)})

        tool_call = ToolCall.new("call_1", "submit_result", JSON.encode!(submitted))
        {:ok, response(%Message{role: :assistant, content: [], tool_calls: [tool_call]}, :tool_calls)}
      end)
      |> expect(:generate_text, fn _model, _context, _opts ->
        {:ok, response(%Message{role: :assistant, content: [ContentPart.text("done")], tool_calls: nil}, :stop)}
      end)

      assert {:ok, %{verdict: "approve"}} =
               Condukt.run("Decide.", input: %{}, output: @output_schema, tools: [passthrough])

      assert_receive {:tools_seen, names}
      assert "passthrough" in names
      assert "submit_result" in names
    end

    test "returns :no_result_submitted when the model never calls submit_result" do
      ReqLLM
      |> expect(:generate_text, fn _model, _context, _opts ->
        {:ok, response(%Message{role: :assistant, content: [ContentPart.text("nope")], tool_calls: nil}, :stop)}
      end)

      assert {:error, :no_result_submitted} =
               Condukt.run("Decide.", input: %{}, output: @output_schema)
    end

    test "returns :invalid_output when the submitted value fails validation" do
      submitted = %{"verdict" => "maybe", "summary" => "Looks good."}

      ReqLLM
      |> expect(:generate_text, fn _model, _context, _opts ->
        tool_call = ToolCall.new("call_1", "submit_result", JSON.encode!(submitted))
        {:ok, response(%Message{role: :assistant, content: [], tool_calls: [tool_call]}, :tool_calls)}
      end)
      |> expect(:generate_text, fn _model, _context, _opts ->
        {:ok, response(%Message{role: :assistant, content: [ContentPart.text("done")], tool_calls: nil}, :stop)}
      end)

      assert {:error, {:invalid_output, %JSV.ValidationError{}}} =
               Condukt.run("Decide.", input: %{}, output: @output_schema)
    end
  end

  describe "telemetry" do
    test "emits :run :start and :stop around an anonymous call" do
      handler_id = "anonymous-run-telemetry-#{inspect(make_ref())}"
      test_pid = self()

      :telemetry.attach_many(
        handler_id,
        [
          [:condukt, :run, :start],
          [:condukt, :run, :stop]
        ],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      # Use the input-validation failure path so we don't need ReqLLM mocks.
      assert {:error, {:invalid_input, _}} =
               Condukt.run("task",
                 input: %{},
                 input_schema: %{type: "object", required: ["x"], properties: %{x: %{type: "string"}}}
               )

      assert_receive {:telemetry, [:condukt, :run, :start], %{system_time: _}, %{structured?: false, input?: true}}

      assert_receive {:telemetry, [:condukt, :run, :stop], %{duration: _}, %{structured?: false, input?: true}}

      :telemetry.detach(handler_id)
    end
  end

  describe "Condukt.run/2 dispatch" do
    test "delegates to Condukt.Session when first argument is an agent pid" do
      defmodule DummyAgent do
        use Condukt
      end

      ReqLLM
      |> expect(:generate_text, fn _model, _context, _opts ->
        {:ok, response(%Message{role: :assistant, content: [ContentPart.text("from session")], tool_calls: nil}, :stop)}
      end)

      {:ok, pid} = DummyAgent.start_link(load_project_instructions: false)

      assert {:ok, "from session"} = Condukt.run(pid, "hi")

      GenServer.stop(pid)
    end
  end

  defp response(message, finish_reason) do
    %Response{
      id: "resp_#{System.unique_integer([:positive])}",
      model: "test:model",
      context: nil,
      message: message,
      object: nil,
      stream?: false,
      stream: nil,
      usage: nil,
      finish_reason: finish_reason,
      provider_meta: %{},
      error: nil
    }
  end
end
