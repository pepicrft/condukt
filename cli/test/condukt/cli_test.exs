defmodule Condukt.CLITest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  defp run(argv), do: Condukt.CLI.main(argv, halt: fn code -> code end)

  test "help succeeds and describes every command" do
    output = capture_io(fn -> assert run(["--help"]) == 0 end)

    assert output =~ "condukt exec"
    assert output =~ "condukt acp"
    assert output =~ "import-pi-credentials"
  end

  test "version prints the name and version" do
    output = capture_io(fn -> assert run(["--version"]) == 0 end)

    assert output =~ "condukt "
  end

  test "an unknown command fails with a message on standard error" do
    output = capture_io(:stderr, fn -> assert run(["teleport"]) == 1 end)

    assert output =~ "condukt: unknown command: teleport"
  end

  test "connecting a provider other than OpenRouter is refused" do
    output = capture_io(:stderr, fn -> assert run(["connect", "acme"]) == 1 end)

    assert output =~ "only OpenRouter is supported"
  end

  test "reading a missing file fails with a message on standard error" do
    output = capture_io(:stderr, fn -> assert run(["read", "definitely-not-here.txt"]) == 1 end)

    assert output =~ "could not read"
  end

  test "listing an unreadable workspace fails with a message on standard error" do
    output = capture_io(:stderr, fn -> assert run(["files", "--cwd", "/definitely/not/here"]) == 1 end)

    assert output =~ "could not list"
  end

  # A test run has no terminal, which is the same situation as a wrapped binary
  # launched from a pipe or a service manager. The interface has to report that
  # and set an exit code rather than take the process down with it, and it has
  # to do so whether or not the caller traps exits.
  test "starting the interface without a terminal reports why and exits non-zero" do
    output = capture_io(:stderr, fn -> assert run([]) == 1 end)

    assert output =~ "could not start the terminal interface"
  end
end
