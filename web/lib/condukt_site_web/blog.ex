defmodule ConduktSiteWeb.Blog do
  @moduledoc """
  Resolves blog post routes to Markdown files under `priv/blog/posts`.

  A route such as `/blog/agent-session-secrets` resolves to
  `posts/agent-session-secrets.md`. Path segments are validated before any
  filesystem access so a request cannot escape the blog root.
  """

  alias ConduktSiteWeb.Blog.Cache
  alias ConduktSiteWeb.Blog.Markdown

  @type post :: Markdown.t()

  @spec list_posts() :: [post()]
  def list_posts do
    root()
    |> Path.join("posts/*.md")
    |> Path.wildcard()
    |> Enum.map(&Cache.get/1)
    |> Enum.sort_by(& &1.date, {:desc, Date})
  end

  @spec get_post(String.t()) :: {:ok, post()} | :error
  def get_post(slug) do
    if safe?(slug) do
      file = Path.join([root(), "posts", slug <> ".md"])

      if File.regular?(file) do
        {:ok, file |> Cache.get() |> Map.put(:source_path, Path.relative_to(file, root()))}
      else
        :error
      end
    else
      :error
    end
  end

  @spec source_path(String.t()) :: {:ok, Path.t()} | :error
  def source_path(slug) do
    if safe?(slug) do
      file = Path.join([root(), "posts", slug <> ".md"])

      if File.regular?(file), do: {:ok, file}, else: :error
    else
      :error
    end
  end

  @spec root() :: Path.t()
  def root, do: Application.app_dir(:condukt_site, "priv/blog")

  defp safe?(slug) do
    is_binary(slug) and slug not in ["", ".", ".."] and
      not String.contains?(slug, ["/", "\\"])
  end
end
