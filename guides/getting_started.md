# Getting Started

Condukt is a framework for building AI agents in Elixir. Agents are OTP
processes that can reason with an LLM, call tools, and orchestrate workflows.

This guide walks through installing Condukt, defining your first agent, and
running a prompt end to end.

## Install

Add `:condukt` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:condukt, "~> 0.10"}
  ]
end
```

Then fetch dependencies:

```sh
mix deps.get
```

## Configure an API key

Condukt uses [ReqLLM](https://github.com/agentjido/req_llm), which auto
discovers provider keys from the environment:

```sh
export ANTHROPIC_API_KEY="sk-ant-..."
```

You can also pass `:api_key` per agent or set it in `config :condukt`. See
the [Providers](providers.md) guide for the full list of supported backends.

## Define an agent

```elixir
defmodule MyApp.CodingAgent do
  use Condukt

  @impl true
  def tools do
    Condukt.Tools.coding_tools()
  end
end
```

`use Condukt` wires the module to a `GenServer` backed by `Condukt.Session`
and provides defaults for `system_prompt/0`, `model/0`, `thinking_level/0`,
`init/1`, and `handle_event/2`. Override what you need.

## Start the agent

```elixir
{:ok, agent} =
  MyApp.CodingAgent.start_link(
    api_key: System.fetch_env!("ANTHROPIC_API_KEY"),
    system_prompt: "You are an expert software engineer."
  )
```

Common options to `start_link/1`:

* `:api_key` overrides `config :condukt, :api_key`
* `:model` accepts the ReqLLM `provider:model` format
* `:cwd` sets the working directory used by file and shell tools
* `:session_store` enables conversation persistence (see [Sessions and Persistence](sessions_and_persistence.md))
* `:compactor` keeps context bounded over long runs (see [Compaction](compaction.md))
* `:redactor` strips secrets from outbound messages (see [Redaction](redaction.md))

## Run a prompt

```elixir
{:ok, response} = Condukt.run(agent, "Create a GenServer that manages a counter.")
```

`Condukt.run/3` runs the agent loop until the model stops calling tools and
returns the final assistant message.

## Stream events

```elixir
agent
|> Condukt.stream("Add docs to the counter module.")
|> Stream.each(fn
  {:text, chunk} -> IO.write(chunk)
  {:tool_call, name, _id, _args} -> IO.puts("\nUsing tool: #{name}")
  :done -> IO.puts("\nDone")
  _ -> :ok
end)
|> Stream.run()
```

The full event vocabulary is described in [Streaming and Events](streaming_and_events.md).

## Add it to a supervision tree

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      {MyApp.CodingAgent,
        api_key: System.fetch_env!("ANTHROPIC_API_KEY"),
        system_prompt: "You are a helpful coding assistant."}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

From here, browse the rest of the guides for deeper coverage of each feature.
