defmodule Condukt.WorkflowsTest do
  use ExUnit.Case, async: true

  alias Condukt.Workflows

  @moduletag :tmp_dir

  describe "run/3" do
    test "runs a workflow that calls run_cmd and returns its stdout", %{tmp_dir: dir} do
      path = Path.join(dir, "hello.star")

      File.write!(path, """
      def run(inputs):
          result = run_cmd(["echo", "hello, " + inputs["name"]])
          return result["stdout"]

      workflow(inputs = {"name": {"type": "string"}})
      """)

      assert {:ok, "hello, world\n"} = Workflows.run(path, %{"name" => "world"})
    end

    test "supports control flow over real step outputs", %{tmp_dir: dir} do
      path = Path.join(dir, "branch.star")

      File.write!(path, """
      def run(inputs):
          result = run_cmd(["echo", inputs["mode"]])
          if result["stdout"].strip() == "approve":
              return "approved"
          else:
              return "rejected"

      workflow(inputs = {"mode": {"type": "string"}})
      """)

      assert {:ok, "approved"} = Workflows.run(path, %{"mode" => "approve"})
      assert {:ok, "rejected"} = Workflows.run(path, %{"mode" => "deny"})
    end

    test "errors when the file does not call workflow(...)", %{tmp_dir: dir} do
      path = Path.join(dir, "no_marker.star")
      File.write!(path, "def run(inputs):\n    return inputs\n")

      assert {:error, message} = Workflows.run(path, %{})
      assert message =~ "workflow(...)"
    end

    test "errors when the file does not define run/1", %{tmp_dir: dir} do
      path = Path.join(dir, "no_run.star")
      File.write!(path, "workflow(inputs = {})\n")

      assert {:error, message} = Workflows.run(path, %{})
      assert message =~ "run(inputs)"
    end

    test "returns a structured error for parse failures", %{tmp_dir: dir} do
      path = Path.join(dir, "bad.star")
      File.write!(path, "def run(:")

      assert {:error, _reason} = Workflows.run(path, %{})
    end

    test "errors when the file is missing" do
      assert {:error, {:read_failed, "/nope/missing.star", :enoent}} =
               Workflows.run("/nope/missing.star", %{})
    end
  end

  describe "check/1" do
    test "returns :ok for a valid file", %{tmp_dir: dir} do
      path = Path.join(dir, "ok.star")

      File.write!(path, """
      def run(inputs):
          return inputs

      workflow(inputs = {})
      """)

      assert :ok = Workflows.check(path)
    end

    test "returns an error for a parse failure", %{tmp_dir: dir} do
      path = Path.join(dir, "bad.star")
      File.write!(path, "def run(:")

      assert {:error, _reason} = Workflows.check(path)
    end
  end
end
