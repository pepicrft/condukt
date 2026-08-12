defmodule ConduktSite.Repo do
  use Ecto.Repo,
    otp_app: :condukt_site,
    adapter: Ecto.Adapters.Postgres
end
