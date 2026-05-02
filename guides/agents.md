# Agents

An agent is a module that does `use Condukt`. Each agent runs as its own
`GenServer` backed by `Condukt.Session`, which manages the conversation
history, the tool loop, and any optional features (sessions, compaction,
redaction).

## The behaviour

`use Condukt` exposes the following optional callbacks, all with defaults:

| Callback | Default | Purpose |
| -------- | ------- | ------- |
| `system_prompt/0` | `nil` | Static system prompt for the agent. |
| `tools/0` | `[]` | List of tool modules or `{module, opts}` tuples. |
| `model/0` | `"anthropic:claude-sonnet-4-20250514"` | ReqLLM `provider:model` identifier. |
| `thinking_level/0` | `:medium` | One of `:off`, `:minimal`, `:low`, `:medium`, `:high`. |
| `init/1` | identity | Called with the keyword opts at startup. |
| `handle_event/2` | no op | Receives events as they happen during a run. |

You only override what you need:

```elixir
defmodule MyApp.ResearchAgent do
  use Condukt

  @impl true
  def system_prompt do
    "You are a careful research assistant. Always cite sources."
  end

  @impl true
  def tools do
    [Condukt.Tools.Read, Condukt.Tools.Bash]
  end

  @impl true
  def model, do: "anthropic:claude-sonnet-4-20250514"
end
```

## Starting an agent

```elixir
{:ok, agent} =
  MyApp.ResearchAgent.start_link(
    api_key: System.fetch_env!("ANTHROPIC_API_KEY"),
    cwd: "/path/to/project"
  )
```

Resolution order for configuration is:

1. Options passed to `start_link/1`
2. `config :condukt, ...`
3. Module callback defaults

## Common options

```elixir
MyApp.ResearchAgent.start_link(
  api_key: "sk-ant-...",                        # Provider key
  model: "anthropic:claude-sonnet-4-20250514",  # ReqLLM model id
  base_url: "http://localhost:11434/v1",        # Override provider URL
  system_prompt: "You are helpful.",            # Static prompt
  thinking_level: :medium,                      # Thinking budget
  load_project_instructions: true,              # See Project Instructions guide
  cwd: "/path/to/project",                      # Tool working directory
  session_store: Condukt.SessionStore.Memory,   # See Sessions guide
  compactor: {Condukt.Compactor.Sliding, keep: 40}, # See Compaction guide
  redactor: Condukt.Redactors.Regex,            # See Redaction guide
  name: MyApp.ResearchAgent                     # GenServer name
)
```

## Public API

The `Condukt` module forwards these calls to `Condukt.Session`:

* `Condukt.run/3` runs a prompt to completion
* `Condukt.stream/3` returns a lazy stream of events
* `Condukt.history/1` returns the current conversation history
* `Condukt.clear/1` clears history
* `Condukt.abort/1` aborts the current operation
* `Condukt.compact/1` runs the configured compactor
* `Condukt.steer/2` injects a message mid run, skipping remaining tool calls
* `Condukt.follow_up/2` queues a message to be delivered after the current run

## Handling events in the agent module

Override `handle_event/2` to react to events without subscribing to the stream:

```elixir
@impl true
def handle_event({:tool_call, name, _id, _args}, state) do
  Logger.info("Calling tool: #{name}")
  {:noreply, state}
end

def handle_event(_event, state), do: {:noreply, state}
```

This is the easiest way to add logging, metrics, or pubsub broadcasts.

## Custom `init/1`

`init/1` lets you build per session state when the agent starts. The return
value is stored on the session and passed to `handle_event/2`:

```elixir
@impl true
def init(opts) do
  {:ok, %{started_at: System.monotonic_time(), opts: opts}}
end
```
