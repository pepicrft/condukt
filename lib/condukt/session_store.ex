defmodule Condukt.SessionStore do
  @moduledoc """
  Behaviour for persisting and restoring Condukt sessions.

  Session stores receive the current session snapshot and decide how to
  persist it. Condukt ships with memory and disk-backed implementations,
  and callers can provide their own store modules.
  """

  @callback load(keyword()) :: {:ok, term()} | :not_found | {:error, term()}
  @callback save(term(), keyword()) :: :ok | {:error, term()}
  @callback clear(keyword()) :: :ok | {:error, term()}
  def load(store, default_opts \\ [])

  def load({module, opts}, default_opts) do
    module.load(Keyword.merge(default_opts, opts))
  end

  def load(module, default_opts) when is_atom(module) do
    module.load(default_opts)
  end

  def save(store, snapshot, default_opts \\ [])

  def save({module, opts}, snapshot, default_opts) do
    module.save(snapshot, Keyword.merge(default_opts, opts))
  end

  def save(module, snapshot, default_opts) when is_atom(module) do
    module.save(snapshot, default_opts)
  end

  def clear(store, default_opts \\ [])

  def clear({module, opts}, default_opts) do
    module.clear(Keyword.merge(default_opts, opts))
  end

  def clear(module, default_opts) when is_atom(module) do
    module.clear(default_opts)
  end
end
