defmodule Condukt.CLI.OptionsTest do
  use ExUnit.Case, async: true

  alias Condukt.CLI.Options

  test "exec accepts a positional prompt" do
    assert {:ok, {:exec, options}} = Options.parse(["exec", "inspect the workspace"])
    assert options[:prompt] == "inspect the workspace"
  end

  test "the short prompt option starts headless mode" do
    assert {:ok, {:exec, options}} = Options.parse(["-p", "inspect the workspace"])
    assert options[:prompt] == "inspect the workspace"
  end

  test "exec keeps its flags alongside a positional prompt" do
    assert {:ok, {:exec, options}} = Options.parse(["exec", "do it", "--verbose", "--json"])
    assert options[:prompt] == "do it"
    assert options[:verbose]
    assert options[:json]
  end

  # Attaching by path is the only image route available to a script, a build
  # job, or a remote shell, none of which have a clipboard to read.
  test "exec attaches images by path" do
    assert {:ok, {:exec, options}} = Options.parse(["exec", "look", "-i", "a.png"])
    assert options[:images] == ["a.png"]
  end

  test "exec accepts more than one image" do
    assert {:ok, {:exec, options}} =
             Options.parse(["exec", "compare", "--image", "before.png", "--image", "after.png"])

    assert options[:images] == ["before.png", "after.png"]
  end

  test "a task with no image attaches none" do
    assert {:ok, {:exec, options}} = Options.parse(["exec", "look"])
    assert options[:images] == []
  end

  test "connect can start browser sign-in without a key" do
    assert {:ok, {:connect, "openrouter", nil}} = Options.parse(["connect", "openrouter"])
  end

  test "connect carries an explicit key" do
    assert {:ok, {:connect, "openrouter", "sk-or-v1"}} =
             Options.parse(["connect", "openrouter", "--api-key", "sk-or-v1"])
  end

  test "files and read match the interactive workspace commands" do
    assert {:ok, {:files, nil}} = Options.parse(["files"])
    assert {:ok, {:read, "README.md", nil}} = Options.parse(["read", "README.md"])
    assert {:ok, {:files, "/tmp"}} = Options.parse(["files", "--cwd", "/tmp"])
  end

  test "no arguments starts the terminal interface" do
    assert {:ok, :tui} = Options.parse([])
  end

  test "the protocol server and credential import are their own commands" do
    assert {:ok, :acp} = Options.parse(["acp"])
    assert {:ok, :import_pi_credentials} = Options.parse(["import-pi-credentials"])
  end

  test "help and version short-circuit any subcommand" do
    assert {:help, text} = Options.parse(["--help"])
    assert text =~ "condukt exec"
    assert {:ok, :version} = Options.parse(["--version"])
    assert {:help, _text} = Options.parse(["exec", "something", "--help"])
  end

  test "the colour choice is validated" do
    assert {:ok, {:exec, options}} = Options.parse(["exec", "hi", "--color", "never"])
    assert options[:color] == :never
    assert {:error, message} = Options.parse(["exec", "hi", "--color", "sometimes"])
    assert message =~ "unknown color"
  end

  test "unknown commands and options are reported rather than ignored" do
    assert {:error, message} = Options.parse(["teleport"])
    assert message =~ "unknown command"
    assert {:error, message} = Options.parse(["--nonsense"])
    assert message =~ "unknown option"
  end

  test "read without a path is an error" do
    assert {:error, message} = Options.parse(["read"])
    assert message =~ "requires a path"
  end
end
