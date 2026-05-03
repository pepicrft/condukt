defmodule Condukt.Tools.SubagentTest do
  use ExUnit.Case, async: true

  alias Condukt.Test.LLMProvider
  alias Condukt.Tool
  alias Condukt.Tools.Subagent
  alias ReqLLM.Message
  alias ReqLLM.ToolCall

  defmodule ParentAgent do
    use Condukt

    @impl true
    def tools, do: []
  end

  defmodule ChildAgent do
    use Condukt
  end

  defmodule CrashAgent do
    use Condukt

    @impl true
    def init(_opts), do: {:stop, :boom}
  end

  test "builds a role enum from registered subagents" do
    input_schema = %{
      type: "object",
      properties: %{
        path: %{type: "string"},
        detail: %{type: "string"}
      },
      required: ["path"]
    }

    optional_input_schema = %{
      type: "object",
      properties: %{detail: %{type: "string"}}
    }

    spec =
      Tool.to_spec(
        {Subagent,
         subagents: [
           researcher: {ChildAgent, input: input_schema},
           coder: {ChildAgent, model: "test", input: optional_input_schema}
         ]}
      )

    assert spec.name == "subagent"

    [researcher_schema, coder_schema] = spec.parameters.oneOf

    assert researcher_schema.properties.role.enum == ["researcher"]
    assert researcher_schema.properties.input == input_schema
    assert researcher_schema.required == ["role", "task", "input"]

    assert coder_schema.properties.role.enum == ["coder"]
    assert coder_schema.properties.input == optional_input_schema
    assert coder_schema.required == ["role", "task"]
  end

  test "delegates to a child session and returns its final answer as the tool result" do
    tool_call = ToolCall.new("call_1", "subagent", JSON.encode!(%{"role" => "researcher", "task" => "write notes"}))

    {parent_model, parent_model_id} =
      LLMProvider.model([
        LLMProvider.response(%Message{role: :assistant, content: [], tool_calls: [tool_call]}, :tool_calls),
        LLMProvider.text_response("parent done")
      ])

    {child_model, child_model_id} = LLMProvider.model(LLMProvider.text_response("field notes"))

    {:ok, parent} =
      ParentAgent.start_link(
        model: parent_model,
        subagents: [
          researcher: {ChildAgent, model: child_model, load_project_instructions: false}
        ],
        load_project_instructions: false
      )

    assert {:ok, "parent done"} = Condukt.run(parent, "delegate")

    assert_receive {LLMProvider, :request, ^parent_model_id, _context, parent_opts}
    subagent_tool = Enum.find(parent_opts[:tools], &(&1.name == "subagent"))

    assert get_in(subagent_tool.parameter_schema, ["oneOf", Access.at(0), "properties", "role", "enum"]) == [
             "researcher"
           ]

    assert_receive {LLMProvider, :request, ^child_model_id, child_context, _child_opts}
    assert Enum.any?(child_context.messages, &message_text?(&1, "write notes"))

    assert_receive {LLMProvider, :request, ^parent_model_id, _context, _parent_opts}

    assert Enum.any?(Condukt.history(parent), fn
             %Condukt.Message{role: :tool_result, content: "field notes"} -> true
             _message -> false
           end)

    assert :sys.get_state(parent).subagent_supervisor |> DynamicSupervisor.which_children() == []

    GenServer.stop(parent)
  end

  test "validates structured input and passes optional fields as optional" do
    input_schema = %{
      type: "object",
      properties: %{
        path: %{type: "string"},
        detail: %{type: "string"}
      },
      required: ["path"]
    }

    tool_call =
      ToolCall.new(
        "call_1",
        "subagent",
        JSON.encode!(%{"role" => "researcher", "task" => "inspect", "input" => %{"path" => "README.md"}})
      )

    {parent_model, _parent_model_id} =
      LLMProvider.model([
        LLMProvider.response(%Message{role: :assistant, content: [], tool_calls: [tool_call]}, :tool_calls),
        LLMProvider.text_response("parent done")
      ])

    {child_model, child_model_id} = LLMProvider.model(LLMProvider.text_response("checked"))

    {:ok, parent} =
      ParentAgent.start_link(
        model: parent_model,
        subagents: [
          researcher: {ChildAgent, model: child_model, input: input_schema, load_project_instructions: false}
        ],
        load_project_instructions: false
      )

    assert {:ok, "parent done"} = Condukt.run(parent, "delegate")

    assert_receive {LLMProvider, :request, ^child_model_id, child_context, _child_opts}
    assert Enum.any?(child_context.messages, &message_contains?(&1, ~s("path":"README.md")))
    refute Enum.any?(child_context.messages, &message_contains?(&1, "detail"))

    GenServer.stop(parent)
  end

  test "returns an error when structured input does not match the role schema" do
    input_schema = %{
      type: "object",
      properties: %{path: %{type: "string"}},
      required: ["path"]
    }

    assert {:error, {:invalid_input, %JSV.ValidationError{}}} =
             Tool.execute(
               {Subagent, subagents: [researcher: {ChildAgent, input: input_schema}]},
               %{"role" => "researcher", "task" => "inspect", "input" => %{}},
               %{agent: self(), sandbox: nil, cwd: ".", subagent_supervisor: self()}
             )
  end

  test "returns validated structured output from a child session" do
    output_schema = %{
      type: "object",
      properties: %{
        summary: %{type: "string"},
        follow_up: %{type: "string"}
      },
      required: ["summary"]
    }

    child_submit = ToolCall.new("child_call_1", "submit_result", JSON.encode!(%{"summary" => "field notes"}))

    parent_call =
      ToolCall.new("parent_call_1", "subagent", JSON.encode!(%{"role" => "researcher", "task" => "summarize"}))

    {parent_model, _parent_model_id} =
      LLMProvider.model([
        LLMProvider.response(%Message{role: :assistant, content: [], tool_calls: [parent_call]}, :tool_calls),
        LLMProvider.text_response("parent done")
      ])

    {child_model, _child_model_id} =
      LLMProvider.model([
        LLMProvider.response(%Message{role: :assistant, content: [], tool_calls: [child_submit]}, :tool_calls),
        LLMProvider.text_response("submitted")
      ])

    {:ok, parent} =
      ParentAgent.start_link(
        model: parent_model,
        subagents: [
          researcher: {ChildAgent, model: child_model, output: output_schema, load_project_instructions: false}
        ],
        load_project_instructions: false
      )

    assert {:ok, "parent done"} = Condukt.run(parent, "delegate")

    assert Enum.any?(Condukt.history(parent), fn
             %Condukt.Message{role: :tool_result, content: %{summary: "field notes"}} -> true
             _message -> false
           end)

    GenServer.stop(parent)
  end

  test "returns an error for an unknown role" do
    assert {:error, "no sub-agent registered as writer"} =
             Tool.execute(
               {Subagent, subagents: [researcher: ChildAgent]},
               %{"role" => "writer", "task" => "draft"},
               %{agent: self(), sandbox: nil, cwd: ".", subagent_supervisor: self()}
             )
  end

  test "returns an error when the child cannot start" do
    {:ok, supervisor} = DynamicSupervisor.start_link(strategy: :one_for_one)

    assert {:error, :boom} =
             Tool.execute(
               {Subagent, subagents: [crasher: CrashAgent]},
               %{"role" => "crasher", "task" => "crash"},
               %{agent: self(), sandbox: nil, cwd: ".", subagent_supervisor: supervisor}
             )

    Supervisor.stop(supervisor)
  end

  test "stopping the parent session stops the subagent supervisor and children" do
    {:ok, parent} =
      ParentAgent.start_link(
        subagents: [worker: ChildAgent],
        load_project_instructions: false
      )

    supervisor = :sys.get_state(parent).subagent_supervisor

    {:ok, child} =
      DynamicSupervisor.start_child(supervisor, %{
        id: {__MODULE__, :manual_child},
        start: {Condukt.Session, :start_link, [ChildAgent, [load_project_instructions: false]]},
        restart: :temporary,
        type: :worker
      })

    supervisor_ref = Process.monitor(supervisor)
    child_ref = Process.monitor(child)

    GenServer.stop(parent)

    assert_receive {:DOWN, ^supervisor_ref, :process, ^supervisor, _reason}
    assert_receive {:DOWN, ^child_ref, :process, ^child, _reason}
  end

  defp message_text?(%Message{content: content}, text) when is_list(content) do
    Enum.any?(content, fn
      %{text: ^text} -> true
      _part -> false
    end)
  end

  defp message_text?(%Message{content: text}, text) when is_binary(text), do: true
  defp message_text?(_message, _text), do: false

  defp message_contains?(%Message{content: content}, text) when is_list(content) do
    Enum.any?(content, fn
      %{text: part_text} when is_binary(part_text) -> String.contains?(part_text, text)
      _part -> false
    end)
  end

  defp message_contains?(%Message{content: content}, text) when is_binary(content), do: String.contains?(content, text)
  defp message_contains?(_message, _text), do: false
end
