defmodule Condukt.CompactorTest do
  use ExUnit.Case, async: true

  alias Condukt.Compactor
  alias Condukt.Compactor.{Sliding, ToolResultPrune}
  alias Condukt.Message

  defp tool_call_msg(id, name \\ "read", args \\ %{}) do
    Message.assistant([{:tool_call, id, name, args}])
  end

  describe "Sliding" do
    test "returns messages unchanged when below the keep threshold" do
      messages = for i <- 1..5, do: Message.user("hi #{i}")
      assert {:ok, ^messages} = Sliding.compact(messages, keep: 10)
    end

    test "keeps the last N messages when over the threshold" do
      messages = for i <- 1..30, do: Message.user("hi #{i}")
      {:ok, kept} = Sliding.compact(messages, keep: 5)

      assert length(kept) == 5
      assert Enum.map(kept, & &1.content) == ["hi 26", "hi 27", "hi 28", "hi 29", "hi 30"]
    end

    test "drops orphaned tool results whose tool call was discarded" do
      old = tool_call_msg("call-old")
      old_result = Message.tool_result("call-old", "old result")
      recent = tool_call_msg("call-recent")
      recent_result = Message.tool_result("call-recent", "recent result")

      messages = [Message.user("u1"), old, old_result, Message.user("u2"), recent, recent_result]
      {:ok, kept} = Sliding.compact(messages, keep: 4)

      ids = Enum.map(kept, & &1.tool_call_id)
      assert "call-recent" in ids
      refute "call-old" in ids
      assert length(kept) == 3
    end

    test "uses default keep when no option is provided" do
      messages = for i <- 1..50, do: Message.user("hi #{i}")
      {:ok, kept} = Sliding.compact(messages, [])
      assert length(kept) == 20
    end
  end

  describe "ToolResultPrune" do
    test "elides oversized old tool results and keeps recent ones intact" do
      big = String.duplicate("x", 5_000)
      small = "ok"

      messages = [
        Message.user("u"),
        tool_call_msg("a"),
        Message.tool_result("a", big),
        tool_call_msg("b"),
        Message.tool_result("b", big),
        tool_call_msg("c"),
        Message.tool_result("c", big)
      ]

      {:ok, pruned} = ToolResultPrune.compact(messages, keep_recent: 1, max_size: 1_000)

      [_, _, a_result, _, b_result, _, c_result] = pruned

      assert a_result.content =~ "<elided"
      assert b_result.content =~ "<elided"
      assert c_result.content == big
      assert small == "ok"
    end

    test "leaves small tool results alone even when out of the recent window" do
      messages = [
        tool_call_msg("a"),
        Message.tool_result("a", "tiny"),
        tool_call_msg("b"),
        Message.tool_result("b", "tiny"),
        tool_call_msg("c"),
        Message.tool_result("c", "tiny")
      ]

      {:ok, pruned} = ToolResultPrune.compact(messages, keep_recent: 1, max_size: 1_000)

      assert Enum.all?(pruned, fn
               %Message{role: :tool_result, content: c} -> c == "tiny"
               _ -> true
             end)
    end

    test "encodes non-binary tool result content before measuring size" do
      payload = %{"data" => String.duplicate("y", 5_000)}

      messages = [
        tool_call_msg("a"),
        Message.tool_result("a", payload),
        tool_call_msg("b"),
        Message.tool_result("b", "recent")
      ]

      {:ok, [_, a_result, _, b_result]} =
        ToolResultPrune.compact(messages, keep_recent: 1, max_size: 1_000)

      assert a_result.content =~ "<elided"
      assert b_result.content == "recent"
    end
  end

  describe "Compactor.compact/3" do
    test "dispatches to a bare module" do
      messages = for i <- 1..30, do: Message.user("m #{i}")
      {:ok, result} = Compactor.compact(Sliding, messages)
      assert length(result) == 20
    end

    test "merges tuple options on top of defaults" do
      messages = for i <- 1..30, do: Message.user("m #{i}")
      {:ok, result} = Compactor.compact({Sliding, keep: 3}, messages)
      assert length(result) == 3
    end
  end
end
