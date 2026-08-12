defmodule ConduktSiteWeb.BlogController do
  use ConduktSiteWeb, :controller

  alias ConduktSiteWeb.Blog

  def index(conn, _params) do
    posts = Blog.list_posts()

    conn
    |> blog_layout("Blog")
    |> assign(:posts, posts)
    |> render(:index)
  end

  def show(conn, %{"slug" => slug}) do
    case Blog.get_post(slug) do
      {:ok, post} ->
        conn
        |> blog_layout(post.title || "Blog")
        |> assign(:post, post)
        |> render(:show)

      :error ->
        conn
        |> put_status(:not_found)
        |> blog_layout("Post not found")
        |> assign(:headings, [])
        |> assign(:markdown, "")
        |> render(:not_found)
    end
  end

  defp blog_layout(conn, title) do
    conn
    |> put_layout(false)
    |> assign(:page_title, title)
  end
end
