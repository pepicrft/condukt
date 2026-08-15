defmodule Condukt.CLI.ACPTest do
  use ExUnit.Case, async: true

  alias Condukt.CLI.ACP

  test "prompt text preserves text and resource links" do
    prompt =
      ACP.prompt_text([
        %{"type" => "text", "text" => "Inspect this:"},
        %{"type" => "resource_link", "name" => "readme", "uri" => "file:///workspace/README.md"}
      ])

    assert prompt == "Inspect this:\n[readme](file:///workspace/README.md)"
  end

  test "unsupported blocks are named rather than dropped" do
    assert ACP.prompt_text([%{"type" => "audio"}]) == "[Unsupported prompt content omitted]"
  end

  test "a prompt that is not a list is empty" do
    assert ACP.prompt_text(nil) == ""
  end

  test "initialization reports the agent and protocol version" do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        ACP.dispatch(%{"method" => "initialize", "id" => 1}, state())
      end)

    assert {:ok, response} = JSON.decode(String.trim(output))
    assert response["id"] == 1
    assert response["result"]["protocolVersion"] == 1
    assert response["result"]["agentInfo"]["name"] == "condukt"
    assert response["result"]["agentInfo"]["version"] == "9.9.9"
  end

  test "an unsupported method is answered with an error" do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        ACP.dispatch(%{"method" => "session/cancel", "id" => 7}, state())
      end)

    assert {:ok, response} = JSON.decode(String.trim(output))
    assert response["error"]["code"] == -32_601
    assert response["error"]["message"] =~ "session/cancel"
  end

  test "a notification is answered with silence" do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        ACP.dispatch(%{"method" => "session/cancelled"}, state())
      end)

    assert output == ""
  end

  test "prompting an unknown session is refused" do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        ACP.dispatch(
          %{"method" => "session/prompt", "id" => 3, "params" => %{"sessionId" => "nope"}},
          state()
        )
      end)

    assert {:ok, response} = JSON.decode(String.trim(output))
    assert response["result"]["stopReason"] == "refusal"
  end

  test "a session that could not connect reports why and ends the turn" do
    session_state = %{state() | sessions: %{"s1" => {:error, "Condukt is not connected."}}}

    output =
      ExUnit.CaptureIO.capture_io(fn ->
        ACP.dispatch(
          %{
            "method" => "session/prompt",
            "id" => 4,
            "params" => %{"sessionId" => "s1", "prompt" => [%{"type" => "text", "text" => "hi"}]}
          },
          session_state
        )
      end)

    [notification, response] = output |> String.trim() |> String.split("\n")

    assert {:ok, decoded} = JSON.decode(notification)
    assert decoded["method"] == "session/update"
    assert decoded["params"]["update"]["content"]["text"] == "Condukt is not connected."

    assert {:ok, decoded} = JSON.decode(response)
    assert decoded["result"]["stopReason"] == "end_turn"
  end

  defp state, do: %{sessions: %{}, next_session: 0, version: "9.9.9", opts: []}
end
