defmodule ConduktSiteWeb.BlogControllerTest do
  use ConduktSiteWeb.ConnCase

  alias ConduktSiteWeb.Blog

  test "GET /blog lists the posts sorted by date desc" do
    conn = get(build_conn(), ~p"/blog")
    body = html_response(conn, 200)

    assert body =~ "Notes from the Condukt team"
    [first | _] = Blog.list_posts()
    assert body =~ first.title
  end

  test "GET /blog/:slug renders a single post" do
    [post | _] = Blog.list_posts()
    conn = get(build_conn(), ~p"/blog/#{post.slug}")
    body = html_response(conn, 200)

    assert body =~ post.title
    assert body =~ ~s(data-prose)
  end

  test "GET /blog/:slug returns 404 for an unknown post" do
    conn = get(build_conn(), ~p"/blog/this-post-does-not-exist")
    assert html_response(conn, 404) =~ "not here"
  end
end
