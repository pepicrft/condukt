defmodule Condukt.OperationTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Condukt.Operation
  alias ReqLLM.Message
  alias ReqLLM.Message.ContentPart
  alias ReqLLM.Response
  alias ReqLLM.ToolCall

  setup :set_mimic_from_context
  setup :verify_on_exit!

  defmodule ReviewAgent do
    use Condukt

    @impl true
    def tools, do: []

    @impl true
    def system_prompt, do: "You are a code reviewer."

    operation(:review_pr,
      input: %{
        type: "object",
        properties: %{
          repo: %{type: "string"},
          pr_number: %{type: "integer"}
        },
        required: ["repo", "pr_number"]
      },
      output: %{
        type: "object",
        properties: %{
          verdict: %{type: "string", enum: ["approve", "request_changes", "comment"]},
          summary: %{type: "string"}
        },
        required: ["verdict", "summary"]
      },
      instructions: "Review the PR and report a verdict."
    )
  end

  describe "compile-time declaration" do
    test "generates a function on the agent module for each operation" do
      assert function_exported?(ReviewAgent, :review_pr, 1)
      assert function_exported?(ReviewAgent, :review_pr, 2)
    end

    test "exposes operation metadata via __operations__/0" do
      ops = ReviewAgent.__operations__()
      assert Map.has_key?(ops, :review_pr)
      op = ops[:review_pr]
      assert %Operation{name: :review_pr} = op
      assert op.instructions =~ "Review the PR"
      assert op.input_schema.required == ["repo", "pr_number"]
      assert op.output_schema.required == ["verdict", "summary"]
    end

    test "__operation__/1 returns :error for unknown names" do
      assert :error = ReviewAgent.__operation__(:does_not_exist)
    end
  end

  describe "input validation" do
    test "rejects args missing required fields" do
      assert {:error, {:invalid_input, %JSV.ValidationError{}}} =
               ReviewAgent.review_pr(%{repo: "tuist/condukt"})
    end

    test "rejects args with wrong types" do
      assert {:error, {:invalid_input, %JSV.ValidationError{}}} =
               ReviewAgent.review_pr(%{repo: "tuist/condukt", pr_number: "not-an-integer"})
    end

    test "rejects non-map args" do
      assert {:error, {:invalid_input, _}} = ReviewAgent.review_pr("not a map")
    end

    test "unknown operation returns :unknown_operation error" do
      assert {:error, {:unknown_operation, :missing}} =
               Operation.run(ReviewAgent, :missing, %{})
    end
  end

  describe "end-to-end happy path" do
    test "runs the agent loop, captures submit_result, validates, and returns atomized output" do
      submitted_args = %{"verdict" => "approve", "summary" => "Looks good."}

      ReqLLM
      |> expect(:generate_text, fn _model, _context, opts ->
        # First turn: agent decides to call submit_result with the verdict.
        tool = Enum.find(opts[:tools], &(&1.name == "submit_result"))
        assert tool, "submit_result tool should be registered with ReqLLM"

        tool_call =
          ToolCall.new(
            "call_1",
            "submit_result",
            JSON.encode!(submitted_args)
          )

        message = %Message{
          role: :assistant,
          content: [],
          tool_calls: [tool_call]
        }

        {:ok,
         %Response{
           id: "resp_1",
           model: "test:model",
           context: nil,
           message: message,
           object: nil,
           stream?: false,
           stream: nil,
           usage: nil,
           finish_reason: :tool_calls,
           provider_meta: %{},
           error: nil
         }}
      end)
      |> expect(:generate_text, fn _model, _context, _opts ->
        # Second turn: after the submit tool runs, model emits final text and stops.
        message = %Message{
          role: :assistant,
          content: [ContentPart.text("Done.")],
          tool_calls: nil
        }

        {:ok,
         %Response{
           id: "resp_2",
           model: "test:model",
           context: nil,
           message: message,
           object: nil,
           stream?: false,
           stream: nil,
           usage: nil,
           finish_reason: :stop,
           provider_meta: %{},
           error: nil
         }}
      end)

      assert {:ok, %{verdict: "approve", summary: "Looks good."}} =
               ReviewAgent.review_pr(%{repo: "tuist/condukt", pr_number: 1})
    end

    test "returns :no_result_submitted when the model never calls submit_result" do
      ReqLLM
      |> expect(:generate_text, fn _model, _context, _opts ->
        message = %Message{
          role: :assistant,
          content: [ContentPart.text("I refuse to submit.")],
          tool_calls: nil
        }

        {:ok,
         %Response{
           id: "resp_x",
           model: "test:model",
           context: nil,
           message: message,
           object: nil,
           stream?: false,
           stream: nil,
           usage: nil,
           finish_reason: :stop,
           provider_meta: %{},
           error: nil
         }}
      end)

      assert {:error, :no_result_submitted} =
               ReviewAgent.review_pr(%{repo: "tuist/condukt", pr_number: 1})
    end
  end
end
