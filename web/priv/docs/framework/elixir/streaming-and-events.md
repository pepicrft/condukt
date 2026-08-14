# Streaming and Events

`Condukt.run/3` waits for the agent loop to finish and returns the final
response. `Condukt.stream/3` returns a lazy `Stream` of events, which is the
right shape for chat UIs, LiveView, Phoenix Channels, and CLI output.

## Event vocabulary

| Event | Description |
| ----- | ----------- |
| `:agent_start` | The agent began processing this prompt. |
| `:turn_start` | A new LLM turn is starting. |
| `{:text, chunk}` | A chunk of model text. |
| `{:thinking, chunk}` | A chunk of model reasoning (if the provider exposes it). |
| `{:tool_call, name, id, args}` | The model is calling a tool. |
| `{:tool_result, id, result}` | A tool returned a result. |
| `:turn_end` | The current LLM turn finished. |
| `:agent_end` | The agent stopped its loop. |
| `{:error, reason}` | An error occurred during the run. |
| `:done` | The stream is complete. Always the last event. |

## Streaming to stdout

```elixir
agent
|> Condukt.stream("Explain OTP")
|> Enum.each(fn
  {:text, chunk} -> IO.write(chunk)
  {:thinking, chunk} -> IO.write(IO.ANSI.faint() <> chunk <> IO.ANSI.reset())
  {:tool_call, name, _id, args} -> IO.inspect({name, args}, label: "tool")
  {:tool_result, _id, result} -> IO.inspect(result, label: "result")
  {:error, reason} -> IO.puts("Error: #{inspect(reason)}")
  :done -> IO.puts("\n[done]")
  _ -> :ok
end)
```

## Phoenix LiveView

A common pattern is to stream events from a `Task` and forward them to the
LiveView process:

```elixir
def handle_event("ask", %{"prompt" => prompt}, socket) do
  parent = self()

  Task.start_link(fn ->
    socket.assigns.agent
    |> Condukt.stream(prompt)
    |> Enum.each(&send(parent, {:agent_event, &1}))
  end)

  {:noreply, assign(socket, response: "")}
end

def handle_info({:agent_event, {:text, chunk}}, socket) do
  {:noreply, update(socket, :response, &(&1 <> chunk))}
end

def handle_info({:agent_event, _other}, socket), do: {:noreply, socket}
```

## In agent callbacks

If you only need side effects (logging, telemetry, pubsub) you do not need
to subscribe to the stream. Override `handle_event/2` in the agent module
instead. See the [Agents](agents.md) guide.

## Steering and follow-ups

While a stream is in flight you can:

* `Condukt.steer/2` to inject a message that takes effect after the current
  tool call finishes. Remaining queued tool calls in that turn are skipped.
* `Condukt.follow_up/2` to queue a message that the agent will pick up once
  it finishes the current run.

Both are useful for interactive UIs where users can interrupt or guide the
agent without aborting it.
