defmodule ConduktTest do
  use ExUnit.Case, async: true

  alias Condukt.Test.LLMProvider

  defmodule DummyAgent do
    use Condukt
  end

  test "delegates prompt-first calls to anonymous runs" do
    {model, _model_id} = LLMProvider.model(LLMProvider.text_response("from anonymous"))

    assert {:ok, "from anonymous"} = Condukt.run("hi", model: model)
  end

  test "delegates pid-first calls to Condukt.Session" do
    {model, _model_id} = LLMProvider.model(LLMProvider.text_response("from session"))
    {:ok, pid} = start_supervised({DummyAgent, [model: model, load_project_instructions: false]})

    assert {:ok, "from session"} = Condukt.run(pid, "hi")
  end
end
