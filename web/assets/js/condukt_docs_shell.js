import {
  LitElement,
  html,
} from "https://cdn.jsdelivr.net/gh/lit/dist@3.3.3/core/lit-core.min.js"

export class ConduktDocsShell extends LitElement {
  constructor() {
    super()
    this.abortController = new AbortController()
    this.headingObserver = undefined
  }

  render() {
    return html`<slot></slot>`
  }

  firstUpdated() {
    const {signal} = this.abortController
    this.querySelector("#docs-menu-trigger")?.addEventListener("click", () => this.toggleSidebar(), {signal})
    this.querySelector("#docs-toc-trigger")?.addEventListener("click", () => this.toggleTableOfContents(), {signal})
    this.querySelector("#docs-sidebar-overlay")?.addEventListener("click", () => this.closeSidebar(), {signal})

    this.querySelectorAll("#docs-sidebar a").forEach((link) => {
      link.addEventListener("click", () => this.closeSidebar(), {signal})
    })

    this.querySelectorAll("#docs-mobile-toc a").forEach((link) => {
      link.addEventListener("click", () => this.closeTableOfContents(), {signal})
    })

    this.querySelectorAll("[data-copy-page]").forEach((button) => {
      button.addEventListener("click", () => this.copyPage(button), {signal})
    })

    this.querySelectorAll(".code-window [data-part='copy']").forEach((button) => {
      button.addEventListener("click", () => this.copyCode(button), {signal})
      button.addEventListener("keydown", (event) => {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault()
          button.click()
        }
      }, {signal})
    })

    globalThis.addEventListener("keydown", (event) => {
      if (event.key === "Escape") {
        this.closeSidebar()
        this.closeTableOfContents()
      }
    }, {signal})

    this.observeHeadings()
  }

  disconnectedCallback() {
    this.abortController.abort()
    this.headingObserver?.disconnect()
    super.disconnectedCallback()
  }

  toggleSidebar() {
    if (this.hasAttribute("data-sidebar-open")) {
      this.closeSidebar()
    } else {
      this.setAttribute("data-sidebar-open", "")
      this.querySelector("#docs-sidebar")?.setAttribute("data-mobile-open", "")
      this.querySelector("#docs-menu-trigger")?.setAttribute("aria-expanded", "true")
    }
  }

  closeSidebar() {
    this.removeAttribute("data-sidebar-open")
    this.querySelector("#docs-sidebar")?.removeAttribute("data-mobile-open")
    this.querySelector("#docs-menu-trigger")?.setAttribute("aria-expanded", "false")
  }

  toggleTableOfContents() {
    const tableOfContents = this.querySelector("#docs-mobile-toc")
    const open = tableOfContents?.dataset.state !== "open"
    tableOfContents?.setAttribute("data-state", open ? "open" : "closed")
    this.querySelector("#docs-toc-trigger")?.setAttribute("aria-expanded", String(open))
  }

  closeTableOfContents() {
    this.querySelector("#docs-mobile-toc")?.setAttribute("data-state", "closed")
    this.querySelector("#docs-toc-trigger")?.setAttribute("aria-expanded", "false")
  }

  async copyPage(button) {
    const source = this.querySelector("#docs-page-markdown")?.value
    if (source) await this.copy(source, button)
  }

  async copyCode(button) {
    const source = button.closest(".code-window")?.querySelector("[data-part='copy-source']")?.content.textContent
    if (source) await this.copy(source, button, true)
  }

  async copy(source, button, iconOnly = false) {
    const previousLabel = button.textContent.trim()

    try {
      await this.copyTextToClipboard(source)
      this.showCopyResult(button, "Copied", iconOnly)
    } catch (_error) {
      this.showCopyResult(button, "Copy failed", iconOnly)
    }

    globalThis.setTimeout(() => {
      if (!button.isConnected) return

      if (iconOnly) {
        button.removeAttribute("data-copied")
        button.setAttribute("aria-label", "Copy code")
      } else {
        button.textContent = previousLabel
      }
    }, 1600)
  }

  showCopyResult(button, label, iconOnly) {
    if (iconOnly) {
      button.toggleAttribute("data-copied", label === "Copied")
      button.setAttribute("aria-label", label)
    } else {
      button.textContent = label
    }
  }

  async copyTextToClipboard(source) {
    if (this.copyWithSelection(source)) return

    if (navigator.clipboard?.writeText && globalThis.isSecureContext) {
      await navigator.clipboard.writeText(source)
      return
    }

    throw new Error("Clipboard access is unavailable")
  }

  copyWithSelection(source) {
    const textArea = document.createElement("textarea")
    textArea.value = source
    textArea.setAttribute("readonly", "")
    textArea.style.position = "fixed"
    textArea.style.top = "0"
    textArea.style.left = "-9999px"
    textArea.style.opacity = "0"
    document.body.append(textArea)
    textArea.focus({preventScroll: true})
    textArea.select()
    textArea.setSelectionRange(0, textArea.value.length)

    try {
      return document.execCommand("copy")
    } finally {
      textArea.remove()
    }
  }

  observeHeadings() {
    if (!("IntersectionObserver" in globalThis)) return

    const headings = [...this.querySelectorAll("[data-prose] h2, [data-prose] h3, [data-prose] h4")]
    if (headings.length === 0) return

    this.headingObserver = new IntersectionObserver((entries) => {
      const visible = entries.find((entry) => entry.isIntersecting)
      if (!visible) return

      this.querySelectorAll("#docs-toc a").forEach((link) => {
        link.toggleAttribute("data-active", link.getAttribute("href") === `#${visible.target.id}`)
      })
    }, {rootMargin: "-15% 0px -70% 0px"})

    headings.forEach((heading) => this.headingObserver.observe(heading))
  }
}

if (!customElements.get("condukt-docs-shell")) {
  customElements.define("condukt-docs-shell", ConduktDocsShell)
}
