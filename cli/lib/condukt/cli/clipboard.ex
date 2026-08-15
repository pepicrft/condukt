defmodule Condukt.CLI.Clipboard do
  @moduledoc """
  Reads the system clipboard, including images.

  A terminal never hands an application image bytes. Bracketed paste carries
  text and nothing else, so an image on the clipboard is invisible to the
  interface unless it goes and fetches it. That is what this module does, and it
  is the same approach Pi takes: bind a key, read the clipboard out of band
  through whatever the host offers, and attach what comes back.

  The host tools differ by platform:

    * macOS asks AppleScript for the clipboard as `PNGf` and has it write the
      bytes to a file, which avoids moving binary data through a pipe that
      expects text.
    * Wayland lists the offered types with `wl-paste --list-types` and then
      asks for the best one.
    * X11 does the same through `xclip` and its `TARGETS` selection.

  Every one of them degrades to `:none` rather than raising: a clipboard with no
  image in it is the common case, not an error.
  """

  alias Condukt.CLI.Command

  # Ordered by preference. Anything outside this list is treated as no image
  # rather than passed to a model that would reject it.
  @supported_types ["image/png", "image/jpeg", "image/webp", "image/gif"]

  @read_timeout to_timeout(second: 5)
  @list_timeout to_timeout(second: 1)

  @doc """
  Reads an image from the clipboard.

  Returns `{:ok, %{media_type: media_type, bytes: bytes}}`, or `:none` when the
  clipboard holds no image this platform can offer.

  ## Options

    * `:platform` - overrides the detected platform, for tests
    * `:env` - one-argument function reading an environment variable, for tests
  """
  def read_image(opts \\ []) do
    case platform(opts) do
      :macos -> read_image_via_apple_script()
      :wayland -> read_image_via_wl_paste()
      :x11 -> read_image_via_xclip()
      :unsupported -> :none
    end
  end

  @doc """
  Reads text from the clipboard.

  Returns `{:ok, text}` or `:none`. Used as the fallback when the clipboard
  holds no image, so one key does what the user means either way.
  """
  def read_text(opts \\ []) do
    case platform(opts) do
      :macos -> text_result(Command.run("pbpaste", []))
      :wayland -> text_result(Command.run("wl-paste", ["--no-newline"]))
      :x11 -> text_result(Command.run("xclip", ["-selection", "clipboard", "-o"]))
      :unsupported -> :none
    end
  end

  defp text_result({:ok, ""}), do: :none
  defp text_result({:ok, text}), do: {:ok, text}
  defp text_result(:error), do: :none

  @doc """
  Which clipboard tooling this host offers.

  Wayland and X11 are distinguished by the session's own environment rather than
  by which binary happens to be installed, because a Wayland session commonly
  has `xclip` present but unable to see the real clipboard.
  """
  def platform(opts \\ []) do
    env = Keyword.get(opts, :env, &System.get_env/1)

    case Keyword.get(opts, :platform, os()) do
      :darwin -> :macos
      :linux -> linux_platform(env)
      _other -> :unsupported
    end
  end

  defp os do
    case :os.type() do
      {:unix, :darwin} -> :darwin
      {:unix, _flavour} -> :linux
      _other -> :windows
    end
  end

  defp linux_platform(env) do
    if present?(env.("WAYLAND_DISPLAY")) or env.("XDG_SESSION_TYPE") == "wayland" do
      :wayland
    else
      :x11
    end
  end

  defp present?(value), do: is_binary(value) and value != ""

  # AppleScript writes the bytes itself. Reading them back from a file keeps the
  # binary off a pipe that would otherwise be decoded as text.
  defp read_image_via_apple_script do
    path = temporary_path("png")

    result =
      Command.run("osascript", apple_script_arguments(path), timeout: @read_timeout)

    image = apple_script_image(result, path)
    File.rm(path)
    image
  end

  defp apple_script_image({:ok, "ok"}, path) do
    case File.read(path) do
      {:ok, bytes} when byte_size(bytes) > 0 -> {:ok, %{media_type: "image/png", bytes: bytes}}
      _other -> :none
    end
  end

  defp apple_script_image(_result, _path), do: :none

  defp apple_script_arguments(path) do
    # `set eof` truncates a file the interface may have written earlier in the
    # session, so a smaller image cannot leave a larger one's tail behind.
    [
      "-e",
      "try",
      "-e",
      "set imageData to the clipboard as «class PNGf»",
      "-e",
      "set target to open for access POSIX file #{apple_script_string(path)} with write permission",
      "-e",
      "set eof target to 0",
      "-e",
      "write imageData to target",
      "-e",
      "close access target",
      "-e",
      "return \"ok\"",
      "-e",
      "on error",
      "-e",
      "return \"none\"",
      "-e",
      "end try"
    ]
  end

  defp apple_script_string(value), do: ~s("#{String.replace(value, "\"", "\\\"")}")

  defp read_image_via_wl_paste do
    with {:ok, listing} <- Command.run("wl-paste", ["--list-types"], timeout: @list_timeout),
         media_type when is_binary(media_type) <- preferred_type(String.split(listing, "\n")),
         {:ok, bytes} <-
           Command.run_binary("wl-paste", ["--type", media_type, "--no-newline"], timeout: @read_timeout) do
      image(media_type, bytes)
    else
      _other -> :none
    end
  end

  defp read_image_via_xclip do
    offered =
      case Command.run("xclip", ["-selection", "clipboard", "-t", "TARGETS", "-o"], timeout: @list_timeout) do
        {:ok, listing} -> String.split(listing, "\n")
        :error -> []
      end

    # Falling back to every supported type covers the selection owners that do
    # not answer a TARGETS request but will still hand over an image.
    candidates =
      case preferred_type(offered) do
        nil -> @supported_types
        media_type -> [media_type | @supported_types]
      end

    Enum.reduce_while(candidates, :none, fn media_type, _acc ->
      case Command.run_binary("xclip", ["-selection", "clipboard", "-t", media_type, "-o"], timeout: @read_timeout) do
        {:ok, bytes} -> continue_unless_image(media_type, bytes)
        :error -> {:cont, :none}
      end
    end)
  end

  defp continue_unless_image(media_type, bytes) do
    case image(media_type, bytes) do
      :none -> {:cont, :none}
      found -> {:halt, found}
    end
  end

  defp image(_media_type, ""), do: :none
  defp image(media_type, bytes), do: {:ok, %{media_type: base_type(media_type), bytes: bytes}}

  @doc """
  Picks the best supported image type out of the ones a clipboard offers.

  Returns `nil` when none of them is an image this agent can attach.
  """
  def preferred_type(offered) do
    normalized =
      offered
      |> Enum.map(&(&1 |> String.trim() |> base_type()))
      |> Enum.reject(&(&1 == ""))

    Enum.find(@supported_types, &(&1 in normalized))
  end

  @doc "Supported image media types, in preference order."
  def supported_types, do: @supported_types

  @doc """
  The file extension for a supported image type.

  Returns `nil` for anything else, which is how a caller tells a type it can
  attach from one it cannot.
  """
  def extension_for("image/png"), do: "png"
  def extension_for("image/jpeg"), do: "jpg"
  def extension_for("image/webp"), do: "webp"
  def extension_for("image/gif"), do: "gif"
  def extension_for(_media_type), do: nil

  defp base_type(media_type) do
    media_type |> String.split(";") |> List.first() |> String.trim() |> String.downcase()
  end

  defp temporary_path(extension) do
    name = "condukt-clipboard-#{System.unique_integer([:positive])}.#{extension}"
    Path.join(System.tmp_dir!(), name)
  end
end
