defmodule Condukt.Workflows.WebhookRouterTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias Condukt.Workflows.{Project, Runtime.WebhookRouter, Workflow}

  test "dispatches POST requests to matching webhook workflows" do
    workflow = webhook_workflow()
    project = %Project{workflows: %{workflow.name => workflow}}

    opts =
      WebhookRouter.init(
        project: project,
        runner: fn ^workflow, input -> {:ok, %{"received" => input}} end
      )

    conn =
      :post
      |> conn("/triage", JSON.encode!(%{"issue" => "broken"}))
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> WebhookRouter.call(opts)

    assert conn.status == 200
    assert {:ok, %{"ok" => true, "result" => %{"received" => %{"issue" => "broken"}}}} = JSON.decode(conn.resp_body)
  end

  test "returns 404 when no webhook route matches" do
    opts = WebhookRouter.init(project: %Project{workflows: %{}})

    conn =
      :post
      |> conn("/missing", "{}")
      |> WebhookRouter.call(opts)

    assert conn.status == 404
    assert {:ok, %{"ok" => false, "error" => "not_found"}} = JSON.decode(conn.resp_body)
  end

  defp webhook_workflow do
    %Workflow{
      name: "triage",
      source_path: __ENV__.file,
      triggers: [%{"kind" => "webhook", "path" => "/triage"}]
    }
  end
end
