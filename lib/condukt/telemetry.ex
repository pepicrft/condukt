defmodule Condukt.Telemetry do
  @moduledoc """
  Telemetry integration for Condukt.

  Condukt emits telemetry events that can be used for monitoring,
  logging, and observability.

  ## Events

  ### Agent Events

  - `[:condukt, :agent, :start]` - Agent started processing a prompt
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{agent: module}`

  - `[:condukt, :agent, :stop]` - Agent finished processing
    - Measurements: `%{duration: integer}`
    - Metadata: `%{agent: module}`

  - `[:condukt, :agent, :exception]` - Agent raised an exception
    - Measurements: `%{duration: integer}`
    - Metadata: `%{agent: module, kind: atom, reason: term, stacktrace: list}`

  ### Tool Events

  - `[:condukt, :tool_call, :start]` - Tool call started
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{tool: string}`

  - `[:condukt, :tool_call, :stop]` - Tool call completed
    - Measurements: `%{duration: integer}`
    - Metadata: `%{tool: string}`

  - `[:condukt, :tool_call, :exception]` - Tool call raised an exception
    - Measurements: `%{duration: integer}`
    - Metadata: `%{tool: string, kind: atom, reason: term, stacktrace: list}`

  ### Operation Events

  Wrap a full `Condukt.Operation.run/4` call (input validation, transient
  session run, output validation). The inner LLM loop still emits the
  `[:condukt, :agent, ...]` events for free.

  - `[:condukt, :operation, :start]` - Operation invocation started
    - Measurements: `%{system_time: integer}`
    - Metadata: `%{agent: module, operation: atom}`

  - `[:condukt, :operation, :stop]` - Operation invocation finished
    - Measurements: `%{duration: integer}`
    - Metadata: `%{agent: module, operation: atom}`

  - `[:condukt, :operation, :exception]` - Operation raised an exception
    - Measurements: `%{duration: integer}`
    - Metadata: `%{agent: module, operation: atom, kind: atom, reason: term, stacktrace: list}`

  ## Example: Attaching Handlers

      :telemetry.attach_many(
        "my-agent-handler",
        [
          [:condukt, :agent, :start],
          [:condukt, :agent, :stop],
          [:condukt, :tool_call, :stop]
        ],
        &MyApp.Telemetry.handle_event/4,
        nil
      )
  """

  @doc """
  Executes a function within a telemetry span.

  Emits start, stop, and exception events for the given event name.
  """
  def span(event, metadata, fun) when is_atom(event) and is_map(metadata) and is_function(fun, 0) do
    event_prefix = [:condukt, event]
    start_time = System.monotonic_time()

    :telemetry.execute(
      event_prefix ++ [:start],
      %{system_time: System.system_time()},
      metadata
    )

    try do
      result = fun.()

      :telemetry.execute(
        event_prefix ++ [:stop],
        %{duration: System.monotonic_time() - start_time},
        metadata
      )

      result
    catch
      kind, reason ->
        :telemetry.execute(
          event_prefix ++ [:exception],
          %{duration: System.monotonic_time() - start_time},
          Map.merge(metadata, %{
            kind: kind,
            reason: reason,
            stacktrace: __STACKTRACE__
          })
        )

        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  @doc """
  Emits a telemetry event.
  """
  def emit(event, measurements \\ %{}, metadata \\ %{}) when is_atom(event) do
    :telemetry.execute([:condukt, event], measurements, metadata)
  end
end
