# Sub-agents

A sub-agent is a specialized agent that a parent agent can delegate work to.
The parent model picks a registered role, sends it a task, and receives the
child agent's final answer as a tool result. Each sub-agent is a full
`Condukt.Session` with its own model, system prompt, tools, and conversation
history.

Use a sub-agent when work needs several reasoning steps, but should stay out
of the parent agent's conversation history. Use a normal tool when the work is
a single function call.

## Declaring sub-agents

Agents declare sub-agents with `subagents/0`. The callback mirrors `tools/0`:

```elixir
defmodule MyApp.LeadAgent do
  use Condukt

  @impl true
  def tools, do: Condukt.Tools.read_only_tools()

  @impl true
  def subagents do
    [
      researcher: MyApp.ResearchAgent,
      coder: {MyApp.CoderAgent, model: "anthropic:claude-sonnet-4-20250514"}
    ]
  end
end
```

Each entry is `role: AgentModule` or `role: {AgentModule, opts}`. The role
atom is the identifier the parent model uses. Registration opts are passed to
the child session startup call.

You can also override registrations when starting a session:

```elixir
{:ok, agent} =
  MyApp.LeadAgent.start_link(
    subagents: [
      reviewer: {MyApp.ReviewerAgent, model: "openai:gpt-5.2"}
    ]
  )
```

## The subagent tool

When `subagents/0` returns at least one role, Condukt injects one built-in
tool into the parent agent:

```json
{
  "name": "subagent",
  "parameters": {
    "type": "object",
    "properties": {
      "role": {"type": "string", "enum": ["researcher", "coder"]},
      "task": {"type": "string", "description": "What the sub-agent should do."}
    },
    "required": ["role", "task"]
  }
}
```

The model sees the registered roles in the `role` enum. When it calls the
tool, Condukt starts a child session, runs `Condukt.run(child, task)`, returns
the final response as the tool result, and then terminates the child session.

## Inheritance

By default a child sub-agent inherits these parent session values:

- `:sandbox`
- `:cwd`
- `:api_key`

Registration opts override inherited values:

```elixir
def subagents do
  [
    researcher: {MyApp.ResearchAgent, sandbox: Condukt.Sandbox.Local}
  ]
end
```

The default shared sandbox keeps file operations consistent. A sub-agent that
reads `lib/foo.ex` sees the same filesystem view as the parent unless the
registration overrides `:sandbox` or `:cwd`.

## Supervision

A parent session with sub-agents starts a linked `DynamicSupervisor`.
Sub-agent sessions are started on demand under that supervisor with
`restart: :temporary`.

Properties:

- Stopping the parent session stops the sub-agent supervisor and its children.
- A child that fails to start or crashes returns an error to the parent tool
  call. The parent session keeps running.
- Child sessions are one-shot in this version. They are started for one task
  and terminated after `Condukt.run/2` returns.
- When a model emits multiple tool calls in one turn, Condukt executes them
  concurrently and preserves result order in the conversation history.

## Events

For now, child events are not forwarded to the parent stream. The parent
observes the `subagent` tool call and the matching tool result. Forwarding
child events as tagged parent events can be added later without changing the
declaration API.

## Errors

Unknown roles return:

```elixir
{:error, "no sub-agent registered as writer"}
```

Child start failures and child crashes return `{:error, reason}` from the
tool call. The model receives that error as the tool result and can recover in
the next turn.
