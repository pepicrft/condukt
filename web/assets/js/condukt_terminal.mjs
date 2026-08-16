import {createRepositoryTools} from "./repository_tools.mjs"

// The page's half of the terminal.
//
// Two jobs. It is the executing end of the browser-tool bridge: the agent loop
// runs on the server, declares nothing of its own, and calls back down here for
// everything it can reach. Keeping the tools in the page is what keeps GitHub's
// rate limit per visitor rather than per server, and what keeps the agent's
// reach the page's to decide.
//
// It also owns the composer. Those controls are custom elements holding their
// own state, and the transcript above them re-renders on every streamed
// fragment, so leaving them out of the server's markup is what stops a patch
// from clearing half-typed text.
export const ConduktTerminal = {
  mounted() {
    this.tools = new Map(createRepositoryTools().map((tool) => [tool.name, tool]))
    this.busy = false

    this.handleEvent("condukt:tool", ({token, name, args}) => this.run(token, name, args))
    this.handleEvent("condukt:busy", ({busy}) => this.setBusy(busy))

    this.pushEvent("tools", {
      tools: [...this.tools.values()].map(({name, description, parameters}) => ({
        name,
        description,
        parameters,
      })),
    })

    this.composer()
    this.scrollToLatest()
  },

  updated() {
    this.scrollToLatest()
  },

  composer() {
    const form = this.el.querySelector("#agent-form")
    if (!form) return

    const input = this.el.querySelector("#agent-prompt")
    const send = (event) => {
      event?.preventDefault()
      if (this.busy) return

      const prompt = (input?.value ?? "").trim()
      if (!prompt) return

      this.pushEvent("submit", {prompt})
      input.value = ""
      input.requestUpdate?.()
    }

    form.addEventListener("submit", send)
    this.el.querySelector("#agent-submit")?.addEventListener("click", send)
    input?.addEventListener("keydown", (event) => {
      // Enter sends, shift+Enter is a newline: what every other chat composer
      // does, and the reason this is not a plain form submit.
      if (event.key === "Enter" && !event.shiftKey) send(event)
    })
  },

  setBusy(busy) {
    this.busy = busy

    const form = this.el.querySelector("#agent-form")
    form?.setAttribute("aria-busy", busy ? "true" : "false")
    this.el.querySelector("#agent-submit")?.toggleAttribute("data-busy", busy)
    this.el.querySelector("#agent-status")?.setAttribute("status", busy ? "in_progress" : "success")
  },

  // The transcript is a fixed-height scroller, so a streamed answer has to be
  // followed rather than left above the fold.
  scrollToLatest() {
    const transcript = this.el.querySelector("#agent-transcript")
    if (transcript) transcript.scrollTop = transcript.scrollHeight
  },

  async run(token, name, args) {
    const tool = this.tools.get(name)

    if (!tool) {
      this.pushEvent("tool_result", {token, error: `This page has no tool named ${name}`})
      return
    }

    try {
      const result = await tool.execute(args ?? {})
      this.pushEvent("tool_result", {token, ok: true, result})
    } catch (error) {
      // A failed tool is an answer, not a crash: the agent is told what went
      // wrong and gets to decide what to do about it.
      this.pushEvent("tool_result", {token, error: error?.message ?? String(error)})
    }
  },
}
