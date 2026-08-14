import initCore, {AgentSession} from "./generated/condukt_wasm.js"

let initialization

/**
 * Load Condukt's WebAssembly module once. Passing `moduleOrPath` is useful for
 * hosts that copy the binary to a content delivery path of their own.
 */
export async function initialize(moduleOrPath) {
  initialization ||= loadCore(moduleOrPath).catch((error) => {
    initialization = undefined
    throw error
  })
  await initialization
}

async function loadCore(moduleOrPath) {
  if (moduleOrPath === undefined && globalThis.process?.versions?.node) {
    const {readFile} = await import("node:fs/promises")
    moduleOrPath = await readFile(new URL("./generated/condukt_wasm_bg.wasm", import.meta.url))
  }

  await initCore(moduleOrPath === undefined ? undefined : {module_or_path: moduleOrPath})
}

/**
 * Create a provider-neutral Condukt agent. The page supplies inference and the
 * complete allowlist of tools available in its environment.
 */
export async function createAgent({inference, tools = [], systemPrompt = ""}) {
  if (!inference || typeof inference.complete !== "function") {
    throw new TypeError("Inference with a complete(request) function is required")
  }

  const registry = new Map()
  const definitions = tools.map((tool) => {
    if (!tool?.name || typeof tool.execute !== "function") {
      throw new TypeError("Every tool needs a name and an execute(arguments) function")
    }
    if (registry.has(tool.name)) {
      throw new TypeError(`Tool names must be unique: ${tool.name}`)
    }
    registry.set(tool.name, tool)
    return {
      name: tool.name,
      description: tool.description || "",
      parameters: tool.parameters || {type: "object", properties: {}},
    }
  })

  await initialize()
  const session = new AgentSession({systemPrompt, tools: definitions})
  return new ConduktAgent(session, inference, registry)
}

/**
 * Build a host that sends provider-neutral completion requests to a same-origin
 * web endpoint. The endpoint owns authentication and provider translation.
 */
export function createHttpInference({
  endpoint = "/api/completions",
  model,
  fetch: fetchImplementation = globalThis.fetch,
} = {}) {
  if (typeof fetchImplementation !== "function") {
    throw new TypeError("A fetch implementation is required")
  }

  return {
    async complete(request, {signal} = {}) {
      const token = globalThis.document?.querySelector("meta[name='csrf-token']")?.content
      const response = await fetchImplementation(endpoint, {
        method: "POST",
        credentials: "same-origin",
        signal,
        headers: {
          "content-type": "application/json",
          ...(token ? {"x-csrf-token": token} : {}),
        },
        body: JSON.stringify({...request, ...(model ? {model} : {})}),
      })

      const body = await response.json().catch(() => ({}))
      if (!response.ok) {
        throw new Error(body.error || `Inference request failed with status ${response.status}`)
      }
      return body
    },
  }
}

class ConduktAgent {
  constructor(session, inference, tools) {
    this.session = session
    this.inference = inference
    this.tools = tools
  }

  /** Run one user turn and stream semantic agent events to the host view. */
  async *run(prompt, {signal} = {}) {
    if (!prompt?.trim()) throw new TypeError("A prompt is required")

    let request = this.session.submit(prompt)
    while (true) {
      throwIfAborted(signal)
      const response = await this.inference.complete(request, {signal})
      const turn = this.session.receive_completion(response)

      if (turn.message.content?.trim()) {
        yield {type: "assistant_message", message: turn.message}
      }
      if (turn.type === "complete") {
        yield {type: "complete", message: turn.message}
        return
      }

      const outputs = []
      for (const call of turn.calls) {
        throwIfAborted(signal)
        yield {type: "tool_call", call}

        const tool = this.tools.get(call.name)
        let content
        let isError = false
        try {
          if (!tool) throw new Error(`The page did not register the ${call.name} tool`)
          const args = JSON.parse(call.arguments || "{}")
          const result = await tool.execute(args, {signal, call})
          if (typeof result === "string") {
            content = result
          } else if (result === undefined) {
            content = ""
          } else {
            content = JSON.stringify(result)
          }
        } catch (error) {
          isError = true
          content = error instanceof Error ? error.message : String(error)
        }

        const output = {toolCallId: call.id, content, isError}
        outputs.push(output)
        yield {type: "tool_result", call, output}
      }

      request = this.session.receive_tool_outputs(outputs)
    }
  }

  history() {
    return this.session.history()
  }

  free() {
    this.session.free()
  }
}

function throwIfAborted(signal) {
  if (signal?.aborted) {
    const abortError = typeof DOMException === "function"
      ? new DOMException("The request was aborted", "AbortError")
      : new Error("The request was aborted")
    throw signal.reason || abortError
  }
}
