defmodule Condukt.CLI.Attachment do
  @moduledoc """
  Turns a path into an image the interface can attach.

  This is the route that needs nothing installed. Dragging a file onto a
  terminal makes it type the file's path, and every terminal does that, so a
  path is the one way to hand an agent an image that works on any host, over
  SSH, and inside a container, none of which have a clipboard at all.

  The type is decided by reading the file's leading bytes rather than trusting
  its name: a `.png` that is really a JPEG still attaches correctly, and a
  `.png` that is really a text file is refused instead of being sent to a
  provider that would reject it.
  """

  @doc """
  Reads an image from a path.

  Returns `{:ok, %{media_type: media_type, bytes: bytes}}`, or `:none` when the
  path is not a readable file holding a supported image.
  """
  def from_path(path, root \\ ".") do
    with {:ok, resolved} <- resolve(path, root),
         {:ok, bytes} <- File.read(resolved),
         media_type when is_binary(media_type) <- media_type(bytes) do
      {:ok, %{media_type: media_type, bytes: bytes}}
    else
      _other -> :none
    end
  end

  @doc """
  Reads every path in `text` when all of them are images.

  Returns `{:ok, images}` or `:none`. All or nothing: text that merely mentions
  a screenshot is text, and turning half of it into attachments would lose the
  other half.
  """
  def from_text(text, root \\ ".") do
    case from_path(text, root) do
      {:ok, image} -> {:ok, [image]}
      :none -> from_paths(split_paths(text), root)
    end
  end

  defp from_paths([], _root), do: :none

  defp from_paths(paths, root) do
    images = Enum.map(paths, &from_path(&1, root))

    if Enum.all?(images, &match?({:ok, _image}, &1)) do
      {:ok, Enum.map(images, fn {:ok, image} -> image end)}
    else
      :none
    end
  end

  # A terminal escapes the spaces in a dragged path, so the whole string is
  # tried as one path first and this only runs for genuinely separate entries.
  defp split_paths(text) do
    text |> String.split(~r/(?<!\\)\s+/, trim: true) |> Enum.reject(&(&1 == ""))
  end

  @doc """
  Normalizes a path the way a terminal hands one over.

  Dragging a file quotes it or backslash-escapes its spaces, and a typed one
  often starts with `~`.
  """
  def resolve(path, root \\ ".") do
    resolved =
      path
      |> String.trim()
      |> unquote_path()
      |> String.replace(~r/\\(.)/, "\\1")
      |> Path.expand(root)

    if File.regular?(resolved), do: {:ok, resolved}, else: :none
  end

  defp unquote_path(path) do
    cond do
      quoted?(path, "\"") -> String.slice(path, 1..-2//1)
      quoted?(path, "'") -> String.slice(path, 1..-2//1)
      true -> path
    end
  end

  defp quoted?(path, quote_character) do
    String.length(path) >= 2 and String.starts_with?(path, quote_character) and
      String.ends_with?(path, quote_character)
  end

  @doc """
  Identifies an image from its leading bytes.

  Returns `nil` for anything that is not a supported image, which is how a
  caller tells an image apart from a path that merely ends in `.png`.
  """
  def media_type(<<137, 80, 78, 71, 13, 10, 26, 10, _rest::binary>>), do: "image/png"
  def media_type(<<255, 216, 255, _rest::binary>>), do: "image/jpeg"
  def media_type(<<"GIF87a", _rest::binary>>), do: "image/gif"
  def media_type(<<"GIF89a", _rest::binary>>), do: "image/gif"
  def media_type(<<"RIFF", _size::binary-size(4), "WEBP", _rest::binary>>), do: "image/webp"
  def media_type(_bytes), do: nil
end
