defmodule Condukt.Workflows.IntegrationTest do
  use ExUnit.Case, async: false
  use Mimic

  import Plug.Test

  alias Condukt.Test.LLMProvider
  alias Condukt.Workflows
  alias Condukt.Workflows.Runtime
  alias Condukt.Workflows.Runtime.WebhookRouter

  @moduletag :workflows_nif

  setup :set_mimic_from_context
  setup :verify_on_exit!

  test "loads a project, starts the runtime, and invokes a webhook workflow" do
    root = Path.expand("../../fixtures/workflows_project", __DIR__)

    assert {:ok, project} = Workflows.load_project(root)
    assert [workflow] = Workflows.list(project)
    assert workflow.name == "triage"

    ReqLLM
    |> expect(:generate_text, fn "openai:gpt-4.1-mini", _context, _opts ->
      {:ok, LLMProvider.text_response("triaged")}
    end)

    runtime = start_supervised!({Runtime, project: project, port: 0})
    opts = WebhookRouter.init(project: project)

    conn =
      :post
      |> conn("/triage", JSON.encode!(%{"issue" => "broken"}))
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> WebhookRouter.call(opts)

    assert Process.alive?(runtime)
    assert conn.status == 200
    assert {:ok, %{"ok" => true, "result" => "triaged"}} = JSON.decode(conn.resp_body)
  end
end
