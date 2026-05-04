defmodule Mix.Tasks.Condukt.CheckTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  @moduletag :tmp_dir

  test "prints ok for a valid workflow", %{tmp_dir: dir} do
    path = Path.join(dir, "ok.star")

    File.write!(path, """
    def run(inputs):
        return inputs

    workflow(inputs = {})
    """)

    output =
      capture_io(fn ->
        Mix.Tasks.Condukt.Check.run([path])
      end)

    assert String.trim(output) == "ok: #{path}"
  end

  test "exits with status 1 on a parse error", %{tmp_dir: dir} do
    path = Path.join(dir, "bad.star")
    File.write!(path, "def run(:")

    assert catch_exit(
             capture_io(:stderr, fn ->
               capture_io(fn -> Mix.Tasks.Condukt.Check.run([path]) end)
             end)
           ) == {:shutdown, 1}
  end
end
