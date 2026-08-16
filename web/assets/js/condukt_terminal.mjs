import {createRepositoryTools} from "./repository_tools.mjs"

// The page's half of the browser-tool bridge.
//
// The agent loop runs on the server, but its tools run here. On connect this
// tells the server what this page can do; from then on the server sends a tool
// call as an event, this runs it and pushes the result back under the same
// token.
//
// Keeping the tools here is what keeps GitHub's rate limit per visitor rather
// than per server, and what keeps the agent's reach the page's to decide.
export const ConduktTerminal = {
  mounted() {
    this.tools = new Map(createRepositoryTools().map((tool) => [tool.name, tool]))

    this.handleEvent("condukt:tool", ({token, name, args}) => this.run(token, name, args))

    this.pushEvent(
      "tools",
      {
        tools: [...this.tools.values()].map(({name, description, parameters}) => ({
          name,
          description,
          parameters,
        })),
      },
    )
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
