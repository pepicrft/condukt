defmodule ConduktSiteWeb.Docs do
  @moduledoc """
  Resolves documentation routes to Markdown files under `priv/docs`.

  A route such as `/docs/guide/browser` resolves to either
  `guide/browser.md` or `guide/browser/index.md`. Path segments are validated
  before any filesystem access so a documentation request cannot escape the
  documentation root.
  """

  alias ConduktSiteWeb.Docs.Cache
  alias ConduktSiteWeb.Docs.Markdown

  @spec get_page([String.t()]) :: {:ok, Markdown.t()} | :error
  def get_page(segments) do
    with {:ok, file} <- source_path(segments) do
      page = file |> Cache.get() |> Map.put(:source_path, Path.relative_to(file, root()))
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

  @spec root() :: Path.t()
  def root, do: Application.app_dir(:condukt_site, "priv/docs")

  defp safe?([]), do: false

  defp safe?(segments) do
    Enum.all?(segments, fn segment ->
      segment not in ["", ".", ".."] and not String.contains?(segment, ["/", "\\"])
    end)
  end
end
