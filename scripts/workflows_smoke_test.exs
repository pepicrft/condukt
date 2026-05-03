# Smoke-tests Condukt.Workflows end-to-end without making a real LLM request.
#
# Usage:
#
#   CONDUKT_BASHKIT_DISABLE=1 CONDUKT_WORKFLOWS_BUILD=1 mix run scripts/workflows_smoke_test.exs
#
# What it does:
#
# 1. Loads the fixture workflow project.
# 2. Registers a stub ReqLLM provider in-process.
# 3. Starts the workflow runtime.
# 4. Sends a Plug.Test webhook request through the router.
# 5. Prints the response body for a quick manual sanity check.

defmodule WorkflowSmokeProvider do
  use ReqLLM.Provider,
    id: :condukt_workflows_smoke,
    default_base_url: "http://condukt-workflows-smoke.test"

  alias ReqLLM.Message
  alias ReqLLM.Message.ContentPart
  alias ReqLLM.Response

  @impl true
  def prepare_request(:chat, model, context, opts) do
    IO.puts("==> Stub provider received model #{model.id}")
    IO.puts("==> Tool count: #{length(opts[:tools] || [])}")
    IO.puts("==> Context messages: #{length(context.messages)}")

    response = %Response{
      id: "workflow-smoke-response",
      model: model.id,
      context: nil,
      message: %Message{
        role: :assistant,
        content: [ContentPart.text("workflow smoke ok")],
        tool_calls: nil
      },
      object: nil,
      stream?: false,
      stream: nil,
      usage: nil,
      finish_reason: :stop,
      provider_meta: %{},
      error: nil
    }

    {:ok,
     Req.new(
       method: :post,
       url: default_base_url() <> "/chat",
       adapter: fn request ->
         {request, Req.Response.new(status: 200, body: response)}
       end
     )}
  end

  def prepare_request(operation, _model, _context, _opts) do
    {:error, RuntimeError.exception("unexpected smoke provider operation: #{inspect(operation)}")}
  end
end

ReqLLM.Providers.register(WorkflowSmokeProvider)

root = Path.expand("../test/fixtures/workflows_project", __DIR__)
{:ok, model} = LLMDB.Model.new(%{id: "workflow-smoke", provider: WorkflowSmokeProvider.provider_id()})

{:ok, project} = Condukt.Workflows.load_project(root)

project = %{
  project
  | workflows:
      Map.new(project.workflows, fn {name, workflow} ->
        {name, %{workflow | model: model}}
      end)
}

{:ok, runtime} = Condukt.Workflows.serve(project, port: 0)

opts = Condukt.Workflows.Runtime.WebhookRouter.init(project: project)

conn =
  :post
  |> Plug.Test.conn("/triage", JSON.encode!(%{"issue" => "smoke"}))
  |> Plug.Conn.put_req_header("content-type", "application/json")
  |> Condukt.Workflows.Runtime.WebhookRouter.call(opts)

IO.puts("\n--- webhook response ---")
IO.puts(conn.resp_body)

if Process.alive?(runtime), do: Supervisor.stop(runtime)
