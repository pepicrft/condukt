defmodule Condukt.Secrets.Providers.Env do
  @moduledoc """
  Loads a session secret from the host process environment.

      secrets: [
        GH_TOKEN: {:env, "GH_TOKEN"}
      ]
  """

  @behaviour Condukt.SecretProvider

  @impl Condukt.SecretProvider
  def load(opts) do
    name = Keyword.get(opts, :name) || Keyword.get(opts, :env) || Keyword.get(opts, :ref)

    case name do
      name when is_atom(name) ->
        load(Keyword.put(opts, :name, Atom.to_string(name)))

      name when is_binary(name) and name != "" ->
        case System.fetch_env(name) do
          {:ok, value} -> {:ok, value}
          :error -> {:error, {:missing_env_secret, name}}
        end

      _ ->
        {:error, :env_secret_requires_name}
    end
  end
end
