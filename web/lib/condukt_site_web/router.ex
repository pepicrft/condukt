defmodule ConduktSiteWeb.Router do
  use ConduktSiteWeb, :router

  @content_security_policy Enum.join(
                             [
                               "default-src 'self'",
                               "base-uri 'self'",
                               "connect-src 'self' ws://localhost:* ws://127.0.0.1:* https://api.github.com https://raw.githubusercontent.com",
                               "font-src 'self' https://fonts.gstatic.com",
                               "form-action 'self'",
                               "frame-ancestors 'self'",
                               "frame-src 'self'",
                               "img-src 'self' data:",
                               "object-src 'none'",
                               "script-src 'self' 'wasm-unsafe-eval' https://cdn.jsdelivr.net/npm/@tuist/noora@0.86.0/priv/static/noora-web-components.js https://cdn.jsdelivr.net/gh/lit/dist@3.3.3/core/lit-core.min.js 'sha384-Bh5v5tOligzRcj5lSaylOQfOrIj0Yniwk1Y99S9BlevMFIz7dff2ntuqKyQ/3Nr4'",
                               "style-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net/npm/@tuist/noora@0.86.0/priv/static/tokens.css https://fonts.googleapis.com"
                             ],
                             "; "
                           )

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :put_root_layout, html: {ConduktSiteWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers, %{"content-security-policy" => @content_security_policy}
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :protect_from_forgery
  end

  scope "/", ConduktSiteWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/docs", DocsController, :index
    get "/docs-markdown/*path", DocsMarkdownController, :show
    get "/docs/*path", DocsController, :show
    get "/auth/openrouter", OpenRouterAuthController, :new
    get "/auth/openrouter/callback/:state", OpenRouterAuthController, :callback
    delete "/auth/openrouter", OpenRouterAuthController, :delete
  end

  scope "/api", ConduktSiteWeb do
    pipe_through :api

    post "/completions", CompletionController, :create
  end
end
