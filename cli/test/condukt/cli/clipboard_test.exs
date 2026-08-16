defmodule Condukt.CLI.ClipboardTest do
  use ExUnit.Case, async: true

  alias Condukt.CLI.Clipboard

  describe "choosing a platform" do
    test "macOS uses its own tooling" do
      assert Clipboard.platform(platform: :darwin) == :macos
    end

    test "a Wayland session is detected from its own environment" do
      env = fake_env(%{"WAYLAND_DISPLAY" => "wayland-0"})
      assert Clipboard.platform(platform: :linux, env: env) == :wayland

      env = fake_env(%{"XDG_SESSION_TYPE" => "wayland"})
      assert Clipboard.platform(platform: :linux, env: env) == :wayland
    end

    # A Wayland session usually has xclip installed but unable to see the real
    # clipboard, so the session type decides rather than which binary exists.
    test "anything else on Linux falls back to X11" do
      assert Clipboard.platform(platform: :linux, env: fake_env(%{})) == :x11
      assert Clipboard.platform(platform: :linux, env: fake_env(%{"WAYLAND_DISPLAY" => ""})) == :x11
    end

    test "a platform with no clipboard tooling is unsupported" do
      assert Clipboard.platform(platform: :windows) == :unsupported
    end

    test "an unsupported platform yields nothing rather than raising" do
      assert Clipboard.read_image(platform: :windows) == :none
      assert Clipboard.read_text(platform: :windows) == :none
    end
  end

  describe "choosing an image type" do
    test "prefers the earliest supported type on offer" do
      assert Clipboard.preferred_type(["image/gif", "image/png"]) == "image/png"
      assert Clipboard.preferred_type(["text/plain", "image/jpeg"]) == "image/jpeg"
    end

    test "ignores parameters on the type" do
      assert Clipboard.preferred_type(["image/png;charset=binary"]) == "image/png"
    end

    test "ignores whitespace and blank entries" do
      assert Clipboard.preferred_type(["", "  image/webp  ", ""]) == "image/webp"
    end

    test "an offer with no supported image yields nothing" do
      assert Clipboard.preferred_type(["text/plain", "text/html", "image/tiff"]) == nil
      assert Clipboard.preferred_type([]) == nil
    end
  end

  describe "naming a file for a type" do
    test "every supported type has an extension" do
      for type <- Clipboard.supported_types(), do: assert(Clipboard.extension_for(type))
    end

    test "jpeg is named the way a file system expects" do
      assert Clipboard.extension_for("image/jpeg") == "jpg"
    end

    test "an unsupported type has none" do
      assert Clipboard.extension_for("image/tiff") == nil
    end
  end

  describe "reporting missing tooling" do
    test "macOS never needs anything installed" do
      assert Clipboard.missing_tooling(platform: :darwin) == nil
    end

    test "a Linux desktop is told what would make the key work" do
      linux = [platform: :linux, env: fake_env(%{"WAYLAND_DISPLAY" => "wayland-0"})]

      # Whether this host happens to have the tools decides the answer, so the
      # assertion is on the shape either way.
      assert Clipboard.missing_tooling(linux) in [nil, "wl-clipboard or xclip"]
      assert Clipboard.missing_tooling(platform: :linux, env: fake_env(%{})) in [nil, "xclip"]
    end

    test "a platform with no clipboard at all has nothing to suggest" do
      assert Clipboard.missing_tooling(platform: :windows) == nil
    end
  end

  # The clipboard is shared machine state, so this reads whatever happens to be
  # there rather than putting something in place. It asserts the contract every
  # caller depends on: a result the interface can act on, or `:none`, never a
  # raise and never a blocking wait.
  describe "reading the host clipboard" do
    @tag :clipboard
    test "returns something usable or nothing at all" do
      assert Clipboard.read_image() == :none or match?({:ok, %{media_type: _, bytes: _}}, Clipboard.read_image())
      assert Clipboard.read_text() == :none or match?({:ok, _text}, Clipboard.read_text())
    end
  end

  defp fake_env(values), do: fn name -> Map.get(values, name) end
end
