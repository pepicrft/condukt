# Compaction

Long-running agents accumulate messages that grow past the model's context
window. A compactor keeps the history bounded by dropping or summarising
older messages. Condukt applies the configured compactor after every
completed turn, and `Condukt.compact/1` triggers it manually.

## Configuring a compactor

```elixir
# Keep only the last 40 messages
MyApp.CodingAgent.start_link(
  compactor: {Condukt.Compactor.Sliding, keep: 40}
)

# Replace large old tool result payloads with placeholders
MyApp.CodingAgent.start_link(
  compactor:
    {Condukt.Compactor.ToolResultPrune, keep_recent: 5, max_size: 4_000}
)
```

A bare module is also accepted when the defaults are fine:

```elixir
MyApp.CodingAgent.start_link(compactor: Condukt.Compactor.Sliding)
```

## Built-in compactors

### `Condukt.Compactor.Sliding`

Keeps the most recent N messages and drops everything older. Orphaned tool
result messages (whose paired tool call was dropped) are removed so the
conversation stays valid.

### `Condukt.Compactor.ToolResultPrune`

Replaces oversized historical tool result payloads with a short placeholder.
The surrounding reasoning, user messages, and recent tool results are left
intact. This is the right choice when tool output is large but the model
still benefits from seeing what it asked and what it concluded.

## Implementing a compactor

```elixir
defmodule MyApp.SummarisingCompactor do
  @behaviour Condukt.Compactor

  @impl true
  def compact(messages, _opts) do
    {recent, older} = Enum.split(messages, -10)
    summary = MyApp.Summariser.summarise(older)

    {:ok, [summary | recent]}
  end
end

MyApp.CodingAgent.start_link(compactor: MyApp.SummarisingCompactor)
```

`compact/2` returns `{:ok, messages}` on success or `{:error, reason}` to
abort compaction (the original history is kept).

## Telemetry

Each compaction emits `[:condukt, :compact, :stop]` with measurements:

* `:duration` (native time)
* `:before` (message count before)
* `:after` (message count after)

and metadata `%{agent: pid()}`. Wire this into your telemetry pipeline to
see how often history is being trimmed.
