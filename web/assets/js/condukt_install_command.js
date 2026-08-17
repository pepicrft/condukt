import {
  LitElement,
  html,
  nothing,
} from "https://cdn.jsdelivr.net/gh/lit/dist@3.3.3/core/lit-core.min.js"

// A copyable shell or Elixir line, with light token colouring.
//
// It lived alongside the WebAssembly terminal until that was deleted, which
// took this with it and left the install sections rendering an undefined
// element. It has nothing to do with the agent, so it lives on its own now.
export class ConduktInstallCommand extends LitElement {
  static properties = {
    command: {type: String},
    // Elixir dependency lines have no leading prompt and no shell tokens.
    language: {type: String},
    copied: {state: true},
  }

  constructor() {
    super()
    this.command = ""
    this.language = "shell"
    this.copied = false
  }

  createRenderRoot() {
    return this
  }

  render() {
    return html`
      <noora-card data-part="install-card" class="noora-dark">
        <div data-part="install-command-row">
          ${this.language === "shell"
            ? html`<span data-part="install-prompt" aria-hidden="true">$</span>`
            : nothing}
          <code aria-label=${this.command}>${this.renderCommand()}</code>
          <noora-button variant="secondary" size="small" @click=${this.copyCommand}>
            ${this.copied ? "Copied" : "Copy"}
          </noora-button>
        </div>
      </noora-card>
    `
  }

  async copyCommand() {
    try {
      await navigator.clipboard.writeText(this.command)
      this.copied = true
      window.setTimeout(() => {
        this.copied = false
      }, 1600)
    } catch (_error) {
      this.copied = false
    }
  }

  renderCommand() {
    if (this.language !== "shell") return this.command

    return this.command
      .trim()
      .split(/\s+/)
      .map(
        (token, index) => html`
          ${index === 0 ? nothing : " "}<span data-token=${shellTokenKind(token, index)}
            >${token}</span
          >
        `,
      )
  }
}

function shellTokenKind(token, index) {
  if (index === 0) return "command"
  if (token.startsWith("-")) return "option"
  if (token.includes(":")) return "target"
  return "argument"
}

customElements.define("condukt-install-command", ConduktInstallCommand)
