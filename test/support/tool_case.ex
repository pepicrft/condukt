defmodule Glossia.Agent.ToolCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      use ExUnit.Case, async: true
    end
  end

  setup do
    test_dir = Path.join(System.tmp_dir!(), "glossia_agent_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(test_dir)

    on_exit(fn ->
      File.rm_rf!(test_dir)
    end)

    {:ok, cwd: test_dir}
  end
end
