defmodule ConduktSiteWeb.Docs do
  @moduledoc """
  Resolves documentation routes to Markdown files under `priv/docs`.

  A route such as `/docs/framework/rust/browser` resolves to either
  `framework/rust/browser.md` or `framework/rust/browser/index.md`. Path segments are validated
  before any filesystem access so a documentation request cannot escape the
  documentation root.
  """

  alias ConduktSiteWeb.Docs.Cache
  alias ConduktSiteWeb.Docs.Markdown

  @spec get_page([String.t()]) :: {:ok, Markdown.t()} | :error
  def get_page(segments) do
    with {:ok, file} <- source_path(segments) do
      page =
        file
        |> Cache.get(base_slug(file))
        |> Map.put(:source_path, Path.relative_to(file, root()))

      {:ok, page}
    end
  end

  @spec source_path([String.t()]) :: {:ok, Path.t()} | :error
  def source_path(segments) do
    if safe?(segments) do
      slug = Enum.join(segments, "/")

      [Path.join(root(), slug <> ".md"), Path.join([root(), slug, "index.md"])]
      |> Enum.find(&File.regular?/1)
      |> case do
        nil -> :error
        file -> {:ok, file}
      end
    else
      :error
    end
  end

  @doc """
  Returns the site path a page's relative Markdown links resolve against.

  The base is the directory the page lives in, so `framework/elixir/tools.md`
  resolves `sandbox.md` to `/docs/framework/elixir/sandbox`.
  """
  @spec base_slug(Path.t()) :: String.t()
  def base_slug(file) do
    file
    |> Path.relative_to(root())
    |> Path.dirname()
    |> case do
      "." -> "/docs"
      directory -> "/docs/" <> directory
    end
  end

  @spec root() :: Path.t()
  def root, do: Application.app_dir(:condukt_site, "priv/docs")

  defp safe?([]), do: false

  defp safe?(segments) do
    Enum.all?(segments, fn segment ->
      segment not in ["", ".", ".."] and not String.contains?(segment, ["/", "\\"])
    end)
  end
end
