defmodule Condukt.CLI.AttachmentTest do
  use ExUnit.Case, async: true

  alias Condukt.CLI.Attachment

  @png <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13>>
  @jpeg <<255, 216, 255, 224, 0, 16>>
  @gif "GIF89a" <> <<1, 0, 1, 0>>
  @webp "RIFF" <> <<36, 0, 0, 0>> <> "WEBP" <> <<1, 2>>

  setup do
    root = Path.join(System.tmp_dir!(), "condukt-attachment-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)
    {:ok, root: root}
  end

  describe "identifying an image" do
    test "recognizes every supported format from its leading bytes" do
      assert Attachment.media_type(@png) == "image/png"
      assert Attachment.media_type(@jpeg) == "image/jpeg"
      assert Attachment.media_type(@gif) == "image/gif"
      assert Attachment.media_type("GIF87a" <> <<0>>) == "image/gif"
      assert Attachment.media_type(@webp) == "image/webp"
    end

    test "anything else is not an image" do
      assert Attachment.media_type("just some text") == nil
      assert Attachment.media_type(<<>>) == nil
      assert Attachment.media_type("RIFF" <> <<0, 0, 0, 0>> <> "WAVE") == nil
    end
  end

  describe "reading a path" do
    test "attaches a real image", %{root: root} do
      path = write(root, "shot.png", @png)

      assert {:ok, %{media_type: "image/png", bytes: @png}} = Attachment.from_path(path)
    end

    # The name is a hint, not the truth. A screenshot saved with the wrong
    # extension still has to reach the model as what it actually is.
    test "trusts the bytes over the extension", %{root: root} do
      path = write(root, "screenshot.png", @jpeg)

      assert {:ok, %{media_type: "image/jpeg"}} = Attachment.from_path(path)
    end

    test "refuses a file that is not an image", %{root: root} do
      assert Attachment.from_path(write(root, "notes.png", "hello")) == :none
    end

    test "refuses a path that is not there", %{root: root} do
      assert Attachment.from_path(Path.join(root, "missing.png")) == :none
    end

    test "refuses a directory", %{root: root} do
      assert Attachment.from_path(root) == :none
    end
  end

  # These are the exact shapes a terminal produces when a file is dragged onto
  # it, which is the gesture this route exists to serve.
  describe "paths as a terminal hands them over" do
    test "backslash-escaped spaces", %{root: root} do
      path = write(root, "my shot.png", @png)

      assert {:ok, _image} = Attachment.from_path(String.replace(path, " ", "\\ "))
    end

    test "single and double quotes", %{root: root} do
      path = write(root, "my shot.png", @png)

      assert {:ok, _image} = Attachment.from_path(~s('#{path}'))
      assert {:ok, _image} = Attachment.from_path(~s("#{path}"))
    end

    test "surrounding whitespace", %{root: root} do
      path = write(root, "shot.png", @png)

      assert {:ok, _image} = Attachment.from_path("  #{path}\n")
    end
  end

  describe "reading a pasted line" do
    test "one path becomes one image", %{root: root} do
      assert {:ok, [%{media_type: "image/png"}]} =
               Attachment.from_text(write(root, "shot.png", @png))
    end

    test "several dragged files become several images", %{root: root} do
      first = write(root, "one.png", @png)
      second = write(root, "two.jpg", @jpeg)

      assert {:ok, [%{media_type: "image/png"}, %{media_type: "image/jpeg"}]} =
               Attachment.from_text("#{first} #{second}")
    end

    # Attaching the images and dropping the words around them would lose what
    # the user actually asked, so a line that is not purely paths stays text.
    test "a sentence mentioning a path stays text", %{root: root} do
      path = write(root, "shot.png", @png)

      assert Attachment.from_text("look at #{path} please") == :none
    end

    test "a mix of images and other files stays text", %{root: root} do
      image = write(root, "shot.png", @png)
      notes = write(root, "notes.txt", "hello")

      assert Attachment.from_text("#{image} #{notes}") == :none
    end

    test "ordinary text is left alone" do
      assert Attachment.from_text("why is the footer wrong?") == :none
      assert Attachment.from_text("") == :none
    end
  end

  defp write(root, name, contents) do
    path = Path.join(root, name)
    File.write!(path, contents)
    path
  end
end
