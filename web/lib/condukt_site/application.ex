defmodule ConduktSite.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [ConduktSiteWeb.Telemetry] ++
        repo_children() ++
        [
          ConduktSiteWeb.Docs.Cache,
          ConduktSiteWeb.Blog.Cache,
          {DNSCluster, query: Application.get_env(:condukt_site, :dns_cluster_query) || :ignore},
          {Phoenix.PubSub, name: ConduktSite.PubSub},
          ConduktSiteWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ConduktSite.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp repo_children do
    if Application.get_env(:condukt_site, :start_repo, true), do: [ConduktSite.Repo], else: []
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ConduktSiteWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
