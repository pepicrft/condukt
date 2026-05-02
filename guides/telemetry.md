# Telemetry

Condukt emits `:telemetry` events for the major phases of an agent run.
Attach handlers to feed your existing observability stack: Logger,
`telemetry_metrics`, Prometheus, OpenTelemetry, or anything else.

## Events

| Event | Measurements | Metadata |
| ----- | ------------ | -------- |
| `[:condukt, :agent, :start]` | `system_time` | `:agent`, `:prompt` |
| `[:condukt, :agent, :stop]` | `duration` | `:agent`, `:turns` |
| `[:condukt, :tool_call, :start]` | `system_time` | `:agent`, `:tool`, `:args` |
| `[:condukt, :tool_call, :stop]` | `duration` | `:agent`, `:tool`, `:result` |
| `[:condukt, :compact, :stop]` | `duration`, `before`, `after` | `:agent` |

The exact set may grow over time. Attach broadly with `attach_many/4` so
new events surface in your handlers without code changes.

## Attaching a handler

```elixir
:telemetry.attach_many(
  "condukt-logger",
  [
    [:condukt, :agent, :start],
    [:condukt, :agent, :stop],
    [:condukt, :tool_call, :start],
    [:condukt, :tool_call, :stop],
    [:condukt, :compact, :stop]
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
    counter("condukt.tool_call.stop.count", tags: [:tool])
  ]
end
```

## Tracing tool calls

Tool call start and stop events share an implicit span via the `:telemetry`
span helpers. With OpenTelemetry you can wrap them with a span processor
that turns each `[:condukt, :tool_call, :*]` pair into a span keyed by the
`:tool` metadata.
