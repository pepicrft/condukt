import assert from "node:assert/strict"
import test from "node:test"

import {createAgent, createHttpInference} from "../index.js"

test("runs a browser-provided tool before completing", async () => {
  let completion = 0
  const inference = {
    async complete(request) {
      completion += 1
      if (completion === 1) {
        assert.equal(request.messages.at(-1).content, "What is Condukt?")
        return {
          role: "assistant",
          content: "",
          toolCalls: [{id: "call-1", name: "read_page", arguments: "{}"}],
        }
      }
      assert.equal(request.messages.at(-1).role, "tool")
      return {role: "assistant", content: "Condukt is portable."}
    },
  }

  const agent = await createAgent({
    inference,
    tools: [{
      name: "read_page",
      description: "Read this page",
      parameters: {type: "object", properties: {}},
      execute: () => ({product: "Condukt"}),
    }],
  })
  const events = []
  for await (const event of agent.run("What is Condukt?")) events.push(event)

  assert.deepEqual(events.map((event) => event.type), [
    "tool_call",
    "tool_result",
    "assistant_message",
    "complete",
  ])
  agent.free()
})

test("turns host tool failures into model-visible results", async () => {
  let completion = 0
  const agent = await createAgent({
    inference: {
      async complete(request) {
        completion += 1
        if (completion === 1) {
          return {
            role: "assistant",
            content: "",
            toolCalls: [{id: "call-1", name: "missing", arguments: "{}"}],
          }
        }
        assert.match(request.messages.at(-1).content, /page did not register/)
        return {role: "assistant", content: "That capability is unavailable."}
      },
    },
  })

  const events = []
  for await (const event of agent.run("Try it")) events.push(event)
  assert.equal(events.find((event) => event.type === "tool_result").output.isError, true)
  agent.free()
})

test("accepts browser actions that intentionally return no value", async () => {
  let completion = 0
  const agent = await createAgent({
    inference: {
      async complete(request) {
        completion += 1
        if (completion === 1) {
          return {
            role: "assistant",
            content: "",
            toolCalls: [{id: "call-1", name: "navigate", arguments: "{}"}],
          }
        }
        assert.equal(request.messages.at(-1).content, "")
        return {role: "assistant", content: "Navigation completed."}
      },
    },
    tools: [{
      name: "navigate",
      description: "Navigate without returning a value",
      parameters: {type: "object", properties: {}},
      execute() {},
    }],
  })

  for await (const _event of agent.run("Navigate")) {
    // Consume the complete agent turn.
  }
  agent.free()
})

test("same-origin inference does not require a document object", async () => {
  const inference = createHttpInference({
    model: "example/model",
    fetch: async (_endpoint, request) => {
      assert.equal(request.headers["x-csrf-token"], undefined)
      assert.equal(JSON.parse(request.body).model, "example/model")
      return new Response(JSON.stringify({role: "assistant", content: "done"}), {
        status: 200,
        headers: {"content-type": "application/json"},
      })
    },
  })

  assert.deepEqual(
    await inference.complete({messages: [], tools: []}),
    {role: "assistant", content: "done"},
  )
})

test("keeps one session across consecutive user turns", async () => {
  const agent = await createAgent({
    inference: {
      async complete(request) {
        const latestUser = request.messages.findLast((message) => message.role === "user")
        return {role: "assistant", content: `Answer to ${latestUser.content}`}
      },
    },
  })

  const firstEvents = []
  for await (const event of agent.run("First question")) firstEvents.push(event)

  const secondEvents = []
  for await (const event of agent.run("Second question")) secondEvents.push(event)

  assert.equal(firstEvents.at(-1).message.content, "Answer to First question")
  assert.equal(secondEvents.at(-1).message.content, "Answer to Second question")
  assert.deepEqual(
    agent.history().filter((message) => message.role === "user").map((message) => message.content),
    ["First question", "Second question"],
  )
  agent.free()
})
