---
title: Secrets belong in the session
date: 2026-05-03
description: "Agentic development needs credentials, but giving an agent access to secrets should not mean pasting them into prompts or leaving them in files."
author: The Condukt team
---

A pattern keeps showing up in agentic workflows: the moment the agent needs to do something useful outside the repository, credentials enter the room. Review a pull request with the GitHub CLI. Run a smoke test against a staging database. Hit a private API. Publish a package. Deploy a preview. These are not exotic tasks. They are the normal work of software development, and if agents are going to take more of that work, they will need access to the same credentials humans have been using from terminals and CI systems for years.

The uncomfortable part is that agents change the boundary around those credentials. A human can paste a token into a terminal and have a pretty good understanding of where that value went. An agent operates through prompts, transcripts, tool results, subprocesses, snapshots, compaction, logs, and sometimes remote execution environments. If the value enters the conversation, suddenly every one of those surfaces has to be trusted with it. The problem is not that the model is malicious. The problem is that the value crossed a boundary it did not need to cross.

I think this is one of those areas where convenience can quietly normalize the wrong behavior. A command fails because `GH_TOKEN` is missing, the agent asks what to do, and someone pastes the token into the chat. It works, which is why it is dangerous. The same happens with `.env` files sitting next to the code. They are convenient, and many tools assume them, but agents are very good at reading files. Even when a tool tries to respect ignored files, the boundary is often policy rather than architecture. I do not think we should build agentic systems around the hope that the agent will politely avoid the wrong file.

## The shape is already emerging

What I find interesting is that the industry is converging on a few related patterns without necessarily naming the same abstraction. [Aider](https://aider.chat/docs/config/api-keys.html) accepts API keys through command-line flags, environment variables, `.env` files, and YAML configuration. [Claude Code](https://code.claude.com/docs/en/env-vars) leans heavily on environment variables and settings, including variables that configure the environment used by spawned tools. [GitHub Copilot coding agent](https://docs.github.com/en/enterprise-cloud@latest/copilot/how-tos/copilot-on-github/customize-copilot/customize-cloud-agent/customize-the-agent-environment) takes the cloud-agent version of the same idea: prepare an ephemeral environment, attach variables and secrets to it, then let the agent work inside that prepared space. These are different products, but the direction is similar: secrets should be part of the execution environment, not part of the task description.

[1Password](https://developer.1password.com/docs/cli/reference/commands/run/) gets particularly close to the mental model I like. `op run` resolves secret references and exposes the values as environment variables only to the subprocess it starts. Their [secret reference syntax](https://developer.1password.com/docs/cli/secret-reference-syntax/) keeps the stable address in code while loading the actual value at runtime. That distinction matters. `op://Engineering/GitHub/token` is not a token. It is a pointer that only becomes useful when resolved by an identity that is allowed to read it. MCP authorization points at another version of the same future for remote tools, where OAuth-based delegated access replaces raw secret passing for SaaS APIs. I do not think one mechanism will replace all the others. Local tools will keep speaking environment variables for a long time, and remote tools should move toward delegated authorization. The important bit is that both can meet at the same boundary.

## Sessions are the boundary

In Condukt, that boundary is the session. A session is not just a chat transcript. It is the unit of work that carries the model, tools, project context, sandbox, history, events, and sometimes persistence. That makes it the right place to attach secrets, because secrets are not global. A session reviewing a pull request might need `GH_TOKEN`. A session running a local smoke test might need `DATABASE_URL`. A session editing documentation probably needs nothing. Loading everything into a shell and letting tools discover what they need was tolerable when the shell was operated by a human. It becomes harder to reason about when the shell is operated by an agent that can run arbitrary commands, read wide parts of the filesystem, and turn tool output into context for a model.

That is why we added session secrets to Condukt. The API is intentionally small. An agent can return `secrets/0`, or a caller can pass `:secrets` when starting a session. Each entry maps an environment variable name to a provider-backed source. The provider can be 1Password, the host environment, a static value for tests, Vault, Doppler, AWS Secrets Manager, Google Secret Manager, SOPS, or an internal service. Condukt should not become a 1Password integration. 1Password is one provider. What the session needs is the normalized result: environment variable names and values, resolved by trusted host code before the agent loop starts.

<div class="code-block">{% highlight "elixir" %}secrets: [
  GH_TOKEN: {:one_password, "op://Engineering/GitHub/token"}
]{% endhighlight %}</div>

When the session starts, Condukt resolves the reference. If resolution fails, the session does not start. If it succeeds, command tools receive `GH_TOKEN` in their execution environment, while the model only needs to know that the GitHub CLI is configured. The value is not added to the system prompt, not added to user messages, and not persisted in session snapshots. The virtual sandbox also receives the environment, which matters because sandboxing and secrets are two halves of the same capability boundary. A sandbox controls where code can run and what files it can touch. Secrets control which external systems that code can authenticate with.

## Redaction is a seatbelt

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

Redaction is necessary, but I do not want to oversell it. If a tool subprocess receives `GH_TOKEN`, it can use `GH_TOKEN`. If the agent has access to a shell that receives the token, the agent can run commands that use it. That is the capability we granted. The question is whether the value needs to become text in the conversation. Usually it does not, so Condukt exact-match redacts resolved secret values from tool results before they are stored, streamed, or sent back to the model. If a command accidentally prints the token, history contains `[REDACTED:GH_TOKEN]`, not the token. The model can still understand what happened. It just does not learn the value.

There are limits, and I think it is important to be honest about them. Very short values are not redacted because they create false positives everywhere. If a tool transforms a secret before printing it, exact-match redaction will not catch that. If you expose a powerful long-lived token to a broad `Bash` tool, the agent has that power for the duration of the session. Redaction is a seatbelt, not the road. The road is least privilege: short-lived credentials, scoped tokens, fewer secrets per session, and eventually tool-specific grants where the GitHub CLI receives `GH_TOKEN`, a migration command receives `DATABASE_URL`, and a generic shell receives as little as possible.

The other piece we added is telemetry. When a session resolves secrets, Condukt emits a value-free event with the names that were resolved. When a tool receives secrets, Condukt emits another value-free event with the tool name, the tool call id when available, and the names exposed to that invocation. Not the values. The access. This gives operators something concrete to audit without creating another place where plaintext can leak. I think this is going to matter more as agent sessions move from local experiments into infrastructure that teams run continuously.

What matters here is not the 1Password provider itself. It is the idea that agentic systems need explicit boundaries for capabilities. We talk a lot about context: give the agent more files, more memory, better instructions, better tools. But capabilities deserve the same care. A tool is a capability. A sandbox is a capability boundary. A secret is a capability. If we treat secrets as random strings floating around the environment, we lose the ability to reason about what the agent can actually do.

We want agents to be useful, and usefulness requires access to real systems. But usefulness without boundaries becomes anxiety. You end up wondering what the agent can see, what it can run, and what it might accidentally leak. Secrets belonging to the session is a small step toward making that anxiety smaller. It gives us a place to declare intent, resolve access, observe usage, and keep plaintext out of the model's world. That feels like the right direction: not hiding capabilities from agents, but making them explicit enough that we can trust the systems we are building around them.
