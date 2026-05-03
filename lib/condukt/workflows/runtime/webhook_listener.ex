defmodule Condukt.Workflows.Runtime.WebhookListener do
  @moduledoc """
  Optional Bandit listener for workflow webhook triggers.
  """

  alias Condukt.Workflows.Runtime.WebhookRouter

  @doc false
  def available? do
    Code.ensure_loaded?(Bandit) and Code.ensure_loaded?(Plug.Conn)
  end

  @doc false
  def child_spec(opts) do
    project = Keyword.fetch!(opts, :project)

    bandit_opts =
      [
        plug: {WebhookRouter, project: project},
        port: Keyword.get(opts, :port, 4000),
        scheme: :http,
        startup_log: false
      ]
      |> maybe_put(:ip, Keyword.get(opts, :ip))

    Bandit.child_spec(bandit_opts)
    |> Map.put(:id, __MODULE__)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
