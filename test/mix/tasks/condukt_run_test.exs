defmodule Mix.Tasks.Condukt.RunTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  @moduletag :tmp_dir

  test "runs a workflow file and prints its return value", %{tmp_dir: dir} do
    path = Path.join(dir, "echo.star")

    File.write!(path, """
    def run(inputs):
        return run_cmd(["echo", inputs["msg"]])["stdout"]

    workflow(inputs = {"msg": {"type": "string"}})
    """)

    output =
      capture_io(fn ->
        Mix.Tasks.Condukt.Run.run([path, "--input", ~s({"msg": "ok"})])
      end)

    assert String.trim(output) == "ok"
  end

  test "exits with an error when the file is missing" do
    assert catch_exit(
             capture_io(fn ->
               Mix.Tasks.Condukt.Run.run(["/nope/missing.star"])
             end)
           ) == {:shutdown, 1}
  end
end
