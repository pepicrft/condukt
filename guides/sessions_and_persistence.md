# Sessions and Persistence

Every running agent owns a `Condukt.Session`: the `GenServer` that holds
conversation history, tool configuration, and runtime options. By default
sessions live only for the lifetime of the process. A session store lets you
snapshot and restore them.

## Built-in stores

* `Condukt.SessionStore.Memory` keeps snapshots in ETS. Useful for restoring
  state within a running BEAM (for example after a `GenServer` crash).
* `Condukt.SessionStore.Disk` writes snapshots to disk. Useful for crashing
  recovery, deployments, and CLIs.

```elixir
# Restore within the current VM
{:ok, agent} =
  MyApp.CodingAgent.start_link(
    session_store:
      {Condukt.SessionStore.Memory, key: {:coding_agent, "/tmp/project"}}
  )

# Persist to disk across restarts
{:ok, agent} =
  MyApp.CodingAgent.start_link(
    cwd: "/tmp/project",
    session_store: Condukt.SessionStore.Disk
  )

# Custom path
{:ok, agent} =
  MyApp.CodingAgent.start_link(
    session_store: {Condukt.SessionStore.Disk, path: "/tmp/condukt.session"}
  )
```

When a store is configured, Condukt loads the snapshot at `start_link/1` and
saves a fresh snapshot after every completed turn.

## What a snapshot contains

`Condukt.SessionStore.Snapshot` captures the parts of the session that need
to survive a restart: the message history and the configurable options (such
as model, system prompt, and `cwd`). It does not capture transient state
like in flight tool calls.

## Implementing a store

Implement the `Condukt.SessionStore` behaviour:

```elixir
defmodule MyApp.RedisStore do
  @behaviour Condukt.SessionStore

  @impl true
  def load(opts) do
    case Redix.command(MyApp.Redix, ["GET", key(opts)]) do
      {:ok, nil} -> :not_found
      {:ok, blob} -> {:ok, :erlang.binary_to_term(blob)}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def save(snapshot, opts) do
    Redix.command(MyApp.Redix, ["SET", key(opts), :erlang.term_to_binary(snapshot)])
    :ok
  end

  @impl true
  def clear(opts) do
    Redix.command(MyApp.Redix, ["DEL", key(opts)])
    :ok
  end

  defp key(opts), do: "condukt:" <> Keyword.fetch!(opts, :key)
end
```

Then plug it into the agent:

```elixir
MyApp.CodingAgent.start_link(
  session_store: {MyApp.RedisStore, key: "user:42"}
)
```

## Clearing history

`Condukt.clear/1` resets the conversation. If a session store is configured,
the next save will overwrite the persisted snapshot with the empty state.
