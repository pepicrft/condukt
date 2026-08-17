import {test} from "node:test"
import assert from "node:assert/strict"

import {ConduktTerminal} from "./condukt_terminal.mjs"

// Enough of an element to satisfy the hook: it only ever reaches for four
// nodes by id, listens on two of them, and sets attributes on three.
function node(extra = {}) {
  return {
    listeners: {},
    attributes: {},
    addEventListener(event, handler) {
      ;(this.listeners[event] ??= []).push(handler)
    },
    setAttribute(name, value) {
      this.attributes[name] = value
    },
    toggleAttribute(name, on) {
      if (on) this.attributes[name] = ""
      else delete this.attributes[name]
    },
    emit(event, payload = {}) {
      for (const handler of this.listeners[event] ?? []) handler({...payload, preventDefault() {}})
    },
    ...extra,
  }
}

// A stand-in for the LiveView hook context. The event names and payload keys
// here are the other half of what ConduktSiteWeb.TerminalLive asserts on the
// server; if either side is renamed, one of the two suites should fail.
function mountHook({tools, composer = true} = {}) {
  const pushed = []
  const handlers = new Map()

  const nodes = {
    "#agent-transcript": node({scrollTop: 0, scrollHeight: 900}),
  }

  if (composer) {
    nodes["#agent-form"] = node()
    nodes["#agent-prompt"] = node({value: ""})
    nodes["#agent-submit"] = node()
    nodes["#agent-status"] = node()
  }

  const hook = Object.create(ConduktTerminal)
  hook.el = {querySelector: (selector) => nodes[selector] ?? null}
  hook.pushEvent = (event, payload) => pushed.push({event, payload})
  hook.handleEvent = (event, handler) => handlers.set(event, handler)

  hook.mounted()
  if (tools) hook.tools = new Map(tools.map((tool) => [tool.name, tool]))

  return {
    hook,
    nodes,
    pushed,
    last: () => pushed.at(-1),
    call: (token, name, args) => handlers.get("condukt:tool")({token, name, args}),
    setBusy: (busy) => handlers.get("condukt:busy")({busy}),
  }
}

test("declares the page's tools when it connects", () => {
  const {pushed} = mountHook()

  const declaration = pushed.find(({event}) => event === "tools")
  assert.ok(declaration)

  const names = declaration.payload.tools.map((tool) => tool.name)
  assert.deepEqual(names, ["list_repository_directory", "read_repository_file"])

  for (const tool of declaration.payload.tools) {
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

  assert.deepEqual(harness.last(), {
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

  assert.deepEqual(harness.last(), {
    event: "tool_result",
    payload: {token: "token-2", error: "GitHub returned status 404"},
  })
})

test("a tool this page does not have is refused, not ignored", async () => {
  const harness = mountHook({tools: []})

  await harness.call("token-3", "delete_everything", {})

  assert.equal(harness.last().payload.token, "token-3")
  assert.match(harness.last().payload.error, /no tool named delete_everything/)
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

test("submitting sends the prompt and clears the composer", () => {
  const harness = mountHook()
  harness.nodes["#agent-prompt"].value = "  what is in lib?  "

  harness.nodes["#agent-form"].emit("submit")

  assert.deepEqual(harness.last(), {event: "submit", payload: {prompt: "what is in lib?"}})
  assert.equal(harness.nodes["#agent-prompt"].value, "")
})

test("an empty prompt sends nothing", () => {
  const harness = mountHook()
  harness.nodes["#agent-prompt"].value = "   "
  const before = harness.pushed.length

  harness.nodes["#agent-form"].emit("submit")

  assert.equal(harness.pushed.length, before)
})

test("enter sends, shift+enter does not", () => {
  const harness = mountHook()
  harness.nodes["#agent-prompt"].value = "hello"

  harness.nodes["#agent-prompt"].emit("keydown", {key: "Enter", shiftKey: true})
  assert.equal(harness.pushed.find(({event}) => event === "submit"), undefined)

  harness.nodes["#agent-prompt"].emit("keydown", {key: "Enter", shiftKey: false})
  assert.deepEqual(harness.last(), {event: "submit", payload: {prompt: "hello"}})
})

// A second prompt while the first turn is still running would interleave two
// answers in one transcript.
test("a prompt sent while busy is dropped", () => {
  const harness = mountHook()
  harness.setBusy(true)
  harness.nodes["#agent-prompt"].value = "again"
  const before = harness.pushed.length

  harness.nodes["#agent-form"].emit("submit")

  assert.equal(harness.pushed.length, before)

  harness.setBusy(false)
  harness.nodes["#agent-form"].emit("submit")
  assert.deepEqual(harness.last(), {event: "submit", payload: {prompt: "again"}})
})

test("busy state is reflected on the controls the server never re-renders", () => {
  const harness = mountHook()

  harness.setBusy(true)
  assert.equal(harness.nodes["#agent-form"].attributes["aria-busy"], "true")
  assert.equal(harness.nodes["#agent-submit"].attributes["data-busy"], "")
  assert.equal(harness.nodes["#agent-status"].attributes.status, "in_progress")

  harness.setBusy(false)
  assert.equal(harness.nodes["#agent-form"].attributes["aria-busy"], "false")
  assert.equal(harness.nodes["#agent-submit"].attributes["data-busy"], undefined)
  assert.equal(harness.nodes["#agent-status"].attributes.status, "success")
})

test("the transcript follows a streamed answer", () => {
  const harness = mountHook()
  harness.nodes["#agent-transcript"].scrollTop = 0

  harness.hook.updated()

  assert.equal(harness.nodes["#agent-transcript"].scrollTop, 900)
})

// Before signing in there is no composer, and mounting must not throw looking
// for one: the page still has to declare its tools.
test("mounts without a composer", () => {
  const harness = mountHook({composer: false})

  assert.ok(harness.pushed.find(({event}) => event === "tools"))
})
