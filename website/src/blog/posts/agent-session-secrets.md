---
title: Secrets belong in the session
date: 2026-05-03
description: "Agentic development needs credentials, but giving an agent access to secrets should not mean pasting them into prompts or leaving them in files."
author: The Condukt team
---

A pattern keeps showing up in agentic development workflows: the moment the agent needs to do something useful outside the repository, credentials enter the room.

Review a pull request with `gh`. Run a smoke test against a staging database. Hit a private API. Publish a package. Deploy a preview. These tasks are not exotic. They are the normal work of software development. And if agents are going to take more of that work, they will need access to the same credentials humans have been using from terminals and CI systems for years.

But there is a difference that we need to make more explicit. A human can hold a secret in their head, paste it into a terminal, and understand the social and security implications of where it goes. An agent operates through context, tools, logs, and subprocesses. If we put a secret in the wrong place, it can become part of a prompt, a transcript, a snapshot, a debug file, or a tool result that gets sent back to the model.

This is not a future problem. It is already here.

## The easy mistake

The easiest thing to do is also the worst thing to normalize: "Here is my token, use it."

We have all done some version of that with tools. A command fails because `GH_TOKEN` is missing. The agent asks what to do. You paste a token into the conversation so it can move forward. It works. That is why the pattern is dangerous.

The problem is not that the model is malicious. The problem is that the value crossed a boundary it did not need to cross. It entered the conversation. From that point on, every part of the system that stores, summarizes, compacts, replays, streams, or exports conversation state has to be trusted with that secret.

That is too much trust.

The second easy mistake is putting secrets in files that happen to be near the code. `.env` files are convenient, and many tools assume them. But agents are very good at reading files. If the file is in the workspace, the agent can usually read it. Even when a tool tries to respect ignored files, the boundary is often policy rather than architecture.

We should not design agentic systems around the hope that the agent will politely avoid the wrong file.

## What other tools are doing

The industry is converging on a few shapes.

[Aider](https://aider.chat/docs/config/api-keys.html) accepts API keys through command-line flags, environment variables, `.env` files, or YAML configuration. That is the traditional CLI shape. It is practical and familiar, but it puts a lot of responsibility on the user's shell and filesystem.

[Claude Code](https://code.claude.com/docs/en/env-vars) also leans heavily on environment variables and settings. Some of those variables configure the agent itself, and some configure the environment used by spawned tools. The interesting bit is that environment becomes part of the agent runtime contract. You configure a session, and the tools see the variables they need.

[GitHub Copilot coding agent](https://docs.github.com/en/enterprise-cloud@latest/copilot/how-tos/copilot-on-github/customize-copilot/customize-cloud-agent/customize-the-agent-environment) takes the cloud-agent version of the same idea. The agent gets an ephemeral development environment, backed by GitHub Actions, and you attach variables or secrets to that environment. The secret is not something you paste into the task. It is part of the prepared execution environment.

[1Password](https://developer.1password.com/docs/cli/reference/commands/run/) is even closer to the shape we like. `op run` resolves secret references and makes the values available as environment variables only for the subprocess it starts. Their [secret reference syntax](https://developer.1password.com/docs/cli/secret-reference-syntax/) keeps the stable reference in code while loading the actual value at runtime. This is a better mental model: code carries pointers, not secrets.

Then there is [MCP authorization](https://modelcontextprotocol.io/specification/2025-03-26/basic/authorization), which is moving toward OAuth-based delegated access for remote tools. That makes sense when the agent is calling a SaaS tool through a protocol boundary. The agent should act with a token that represents the user or a specific application, with expiration, scopes, and consent.

These are different implementations, but the direction is similar: do not put plaintext secrets in the prompt. Give the execution environment the minimum credentials it needs, and keep the agent's reasoning context separate from the secret values.

## Why the session is the right boundary

We have been thinking about sessions as the primitive for agents for a while. A session is not just a chat transcript. It is the unit of work. It has a model, tools, project context, a sandbox, history, events, and sometimes persistence.

That makes it the right place to attach secrets.

Secrets are not global. They should not be sprinkled across tool definitions, shell profiles, and random files. They should be scoped to the work being done. If a session reviews a pull request, maybe it needs `GH_TOKEN`. If another session runs a local smoke test, maybe it needs `DATABASE_URL`. If a session edits documentation, it probably needs nothing.

That sounds obvious, but many development environments are still built around the opposite assumption: load everything into the shell and let tools find what they need.

That was tolerable when the shell was operated by a human. It becomes more uncomfortable when the shell is operated by an agent that can run arbitrary commands, read wide parts of the filesystem, and turn tool output into context for a model.

The session boundary gives us a place to be explicit:

- Which secrets exist for this unit of work?
- Where do they come from?
- Which environment variable names should tools see?
- What happens if a tool prints one?
- Are these values persisted anywhere?

Once those questions have answers, the rest of the system can become simpler.

## References, not values

The part we like most about 1Password's design is the secret reference.

`op://Engineering/GitHub/token` is not a token. It is a stable address. It is safe to put in code, documentation, or project configuration because it does not grant access by itself. Access depends on the identity that resolves it.

That distinction matters a lot for agents. We should be able to say:

<div class="code-block">{% highlight "elixir" %}secrets: [
  GH_TOKEN: {:one_password, "op://Engineering/GitHub/token"}
]{% endhighlight %}</div>

and have the runtime do the boring work:

1. Resolve the reference when the session starts.
2. Keep the value inside trusted process memory.
3. Pass it to command tools as `GH_TOKEN`.
4. Redact it if it appears in tool output.
5. Avoid storing it in the session snapshot.

The agent never needs to see the token. It only needs to know that `gh` is configured.

That is a small API choice, but it changes the way the system feels. The developer declares capability. The session resolves it. Tools receive it. The model reasons around it without ingesting it.

## Provider-backed, not provider-owned

Condukt should not become a 1Password integration. That would be the wrong abstraction.

1Password is a provider. Environment variables are a provider. A static value can be a provider for tests. Vault, Doppler, AWS Secrets Manager, Google Secret Manager, SOPS, or an internal service can all be providers. The session should not care.

What the session needs is a normalized result: environment variable names and values.

That gives us a very Elixir-friendly shape. A provider is a behaviour. It receives trusted options and returns `{:ok, value}` or `{:error, reason}`. If it fails, the session does not start. That is much better than starting an agent that later discovers it cannot do the work because a token is missing.

It also keeps ownership in the right place. Your application decides how to authenticate with the secret provider. Your application decides which vaults or paths are available. Condukt only coordinates the session boundary and tool environment.

## Redaction is not authorization

Redaction is necessary, but we do not want to pretend it is a permission model.

If a tool subprocess receives `GH_TOKEN`, it can use `GH_TOKEN`. If the agent has access to a full shell, and the shell has the token, the agent can run commands that use it. That is not a bug. That is the capability we granted.

The question is whether the value needs to become text in the conversation. Usually it does not.

So the runtime should exact-match redact resolved secret values from tool results before they are stored, streamed, or sent back to the model. If a command accidentally prints the token, the history should contain `[REDACTED:GH_TOKEN]`, not the token. The model can still understand what happened: a token was printed. It just does not learn the value.

There are limits. Very short values should not be redacted because they create false positives everywhere. A three-character PIN is better handled by not exposing it to a chatty subprocess in the first place. And if a tool transforms a secret before printing it, exact-match redaction will not catch that.

That is why we see redaction as a seatbelt, not as the road.

The road is least privilege.

## Least privilege has to be practical

Security advice often fails because it asks people to accept too much friction. Developers will not build a ceremony-heavy flow for every local task. They will paste the token, move on, and tell themselves they will clean it up later.

A good secrets API has to make the safer path the easier path.

That means:

- A concise declaration in trusted code.
- Good defaults for common providers.
- No plaintext files.
- No prompt ceremony.
- Failure at session start when a secret cannot be resolved.
- Redaction without the developer having to wire it manually.

It also means accepting that secrets will sometimes be environment variables. We can argue that environment variables are an imperfect primitive, and we would be right. They are inherited by subprocesses. They can leak into debug output. They are coarse.

But they are also the primitive that most developer tools understand. `gh`, `aws`, `stripe`, `flyctl`, `op`, `mix`, test suites, and deploy scripts already know how to read them. If we want agents to work with existing tools, environment variables are the narrow waist.

The important design choice is not whether environment variables exist. They will. The important choice is who resolves them, when they are available, and whether they enter the model context.

## A small change in Condukt

This is why we added session secrets to Condukt.

The API is intentionally small. An agent can return `secrets/0`, or a caller can pass `:secrets` when starting a session. Each entry maps an environment variable name to a provider-backed source.

<div class="code-block">{% highlight "elixir" %}defmodule MyApp.ReviewAgent do
  use Condukt

  @impl true
  def tools do
    [
      Condukt.Tools.Read,
      {Condukt.Tools.Command, command: "gh"}
    ]
  end

  @impl true
  def secrets do
    [
      GH_TOKEN: {:one_password, "op://Engineering/GitHub/token"}
    ]
  end
end{% endhighlight %}</div>

When the session starts, Condukt resolves the secret. `Condukt.Tools.Command` and `Condukt.Tools.Bash` receive it in their execution environment. The session store does not persist it. The model context does not include it. Tool results are redacted if they contain it.

The virtual sandbox also accepts the environment, which matters because secrets and sandboxing are not separate concerns. A sandbox controls where code can run and what files it can touch. Secrets control which outside systems that code can authenticate with. You need both if you want a credible agentic runtime.

This is not the end of the design. It is the beginning of a more explicit model.

## Where this should go

We would like to see this evolve in a few directions.

First, tool-specific grants. A session might have five secrets, but not every tool should receive all five. `gh` needs `GH_TOKEN`. A database migration command needs `DATABASE_URL`. A generic `Bash` tool probably should receive fewer secrets than a scoped `Command` tool. The current model is useful, but the next step is finer-grained exposure.

Second, short-lived credentials. Static tokens are convenient, but agents are a good forcing function for better security. If a session can request a credential that expires in ten minutes and is scoped to one repository, that is better than a long-lived token sitting in a vault.

Third, better audit. If an agent uses a secret, the session should be able to emit a structured event: which environment variable was exposed, to which tool, for which invocation. Not the value. The access. That gives operators something to reason about later.

Fourth, OAuth-native tools. MCP is pointing in this direction. Some tools should not receive secrets as environment variables at all. They should receive delegated access through an authorization flow that binds the user, the tool, and the requested action.

We do not think one mechanism will replace all the others. Local developer tools will keep using environment variables. Remote tools will move toward OAuth. Secret managers will keep being the source of truth. The session is where those worlds meet.

## The broader point

What matters here is not the 1Password integration itself. It is the idea that agentic systems need explicit boundaries for capabilities.

We talk a lot about context. Give the agent more context. Better instructions. Better tools. Better memory. That is all true, but capabilities deserve the same care. A tool is a capability. A sandbox is a capability boundary. A secret is a capability. If we treat secrets as random strings floating around the environment, we lose the ability to reason about what the agent can actually do.

We want agents to be useful. That means they need access to real systems. But usefulness without boundaries becomes anxiety. You end up wondering what the agent can see, what it can run, and what it might accidentally leak.

Secrets belonging to the session is a small step toward making that anxiety smaller. It gives us a place to declare intent, resolve access, and keep plaintext out of the model's world.

That feels like the right direction: not hiding capabilities from agents, but making them explicit enough that we can trust the systems we are building around them.
