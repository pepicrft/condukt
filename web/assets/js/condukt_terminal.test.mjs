import {test} from "node:test"
import assert from "node:assert/strict"

import {ConduktTerminal} from "./condukt_terminal.mjs"

// A stand-in for the LiveView hook context. The names and payload keys here
// are the other half of what ConduktSiteWeb.TerminalLive asserts on the
// server; if either side is renamed, one of the two suites should fail.
function mountHook({tools} = {}) {
  const pushed = []
  const handlers = new Map()

  const hook = Object.create(ConduktTerminal)
  hook.pushEvent = (event, payload) => pushed.push({event, payload})
  hook.handleEvent = (event, handler) => handlers.set(event, handler)

  hook.mounted()
  if (tools) hook.tools = new Map(tools.map((tool) => [tool.name, tool]))

  return {
    pushed,
    call: (token, name, args) => handlers.get("condukt:tool")({token, name, args}),
  }
}

test("declares the page's tools when it connects", () => {
  const {pushed} = mountHook()

  assert.equal(pushed.length, 1)
  const [{event, payload}] = pushed
  assert.equal(event, "tools")

  const names = payload.tools.map((tool) => tool.name)
  assert.deepEqual(names, ["list_repository_directory", "read_repository_file"])

  for (const tool of payload.tools) {
    assert.equal(typeof tool.description, "string")
    assert.equal(tool.parameters.type, "object")
    // The executable half stays here; only the schema crosses the wire.
    assert.equal(tool.execute, undefined)
  }
})

test("runs a tool and pushes its result under the same token", async () => {
  const harness = mountHook({
    tools: [{name: "read_repository_file", execute: async ({path}) => ({path, content: "ok"})}],
  })

  await harness.call("token-1", "read_repository_file", {path: "mix.exs"})

  assert.deepEqual(harness.pushed.at(-1), {
    event: "tool_result",
    payload: {token: "token-1", ok: true, result: {path: "mix.exs", content: "ok"}},
  })
})

test("a tool that throws answers with an error rather than going quiet", async () => {
  const harness = mountHook({
    tools: [
      {
        name: "read_repository_file",
        execute: async () => {
          throw new Error("GitHub returned status 404")
        },
      },
    ],
  })

  await harness.call("token-2", "read_repository_file", {path: "nope"})

  assert.deepEqual(harness.pushed.at(-1), {
    event: "tool_result",
    payload: {token: "token-2", error: "GitHub returned status 404"},
  })
})

test("a tool this page does not have is refused, not ignored", async () => {
  const harness = mountHook({tools: []})

  await harness.call("token-3", "delete_everything", {})

  const {payload} = harness.pushed.at(-1)
  assert.equal(payload.token, "token-3")
  assert.match(payload.error, /no tool named delete_everything/)
})

// The server sends no arguments when the model calls a tool with none.
test("a call with no arguments still runs", async () => {
  let received = "not called"
  const harness = mountHook({
    tools: [{name: "list_repository_directory", execute: async (args) => (received = args)}],
  })

  await harness.call("token-4", "list_repository_directory", undefined)

  assert.deepEqual(received, {})
})
