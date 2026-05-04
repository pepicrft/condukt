# Telemetry

Condukt emits `:telemetry` events for the major phases of an agent run.
Attach handlers to feed your existing observability stack: Logger,
`telemetry_metrics`, Prometheus, OpenTelemetry, or anything else.

## Events

| Event | Measurements | Metadata |
| ----- | ------------ | -------- |
| `[:condukt, :agent, :start]` | `system_time` | `:agent` |
| `[:condukt, :agent, :stop]` | `duration` | `:agent` |
| `[:condukt, :tool_call, :start]` | `system_time` | `:tool` |
| `[:condukt, :tool_call, :stop]` | `duration` | `:tool` |
| `[:condukt, :subagent, :start]` | `system_time` | `:agent`, `:role`, `:child_agent`, `:input?`, `:output?` |
| `[:condukt, :subagent, :stop]` | `duration` | `:agent`, `:role`, `:child_agent`, `:input?`, `:output?`, `:status`, `:error` |
| `[:condukt, :operation, :start]` | `system_time` | `:agent`, `:operation` |
| `[:condukt, :operation, :stop]` | `duration` | `:agent`, `:operation` |
| `[:condukt, :run, :start]` | `system_time` | `:structured?`, `:input?` |
| `[:condukt, :run, :stop]` | `duration` | `:structured?`, `:input?` |
| `[:condukt, :compact, :stop]` | `duration`, `before`, `after` | `:agent` |
| `[:condukt, :secrets, :resolve]` | `count` | `:agent`, `:names` |
| `[:condukt, :secrets, :access]` | `count` | `:agent`, `:tool`, `:tool_call_id`, `:names` |

The exact set may grow over time. Attach broadly with `attach_many/4` so
new events surface in your handlers without code changes.

Secret events are value-free. `:names` contains environment variable names
such as `["GH_TOKEN"]`, never the resolved secret values. `:tool_call_id` is
present when the access comes from a provider-returned tool call.

Sub-agent events are value-free too. They identify the parent agent module,
the delegated role, the child agent module, whether structured input and output
contracts are configured, and whether delegation ended with `:ok` or `:error`.
The `:error` metadata is an atom such as `:invalid_input`, not the rejected
input or output payload.

## Attaching a handler

```elixir
:telemetry.attach_many(
  "condukt-logger",
  [
    [:condukt, :agent, :start],
    [:condukt, :agent, :stop],
    [:condukt, :tool_call, :start],
    [:condukt, :tool_call, :stop],
    [:condukt, :subagent, :start],
    [:condukt, :subagent, :stop],
    [:condukt, :operation, :start],
    [:condukt, :operation, :stop],
    [:condukt, :run, :start],
    [:condukt, :run, :stop],
    [:condukt, :compact, :stop],
    [:condukt, :secrets, :resolve],
    [:condukt, :secrets, :access]
  ],
  fn event, measurements, metadata, _config ->
    Logger.info("#{inspect(event)} #{inspect(measurements)} #{inspect(metadata)}")
  end,
  nil
)
```

Attach this once at application start.

## With `telemetry_metrics`

```elixir
def metrics do
  [
    summary("condukt.agent.stop.duration",
      unit: {:native, :millisecond}
    ),
    summary("condukt.tool_call.stop.duration",
      tags: [:tool],
      unit: {:native, :millisecond}
    ),
    counter("condukt.tool_call.stop.count", tags: [:tool]),
    summary("condukt.subagent.stop.duration", tags: [:agent, :role, :child_agent, :status]),
    counter("condukt.subagent.stop.count", tags: [:agent, :role, :child_agent, :status]),
    counter("condukt.secrets.access.count", tags: [:agent, :tool])
  ]
end
```

## Tracing tool calls

Tool call start and stop events share an implicit span via the `:telemetry`
span helpers. With OpenTelemetry you can wrap them with a span processor
that turns each `[:condukt, :tool_call, :*]` pair into a span keyed by the
`:tool` metadata.
