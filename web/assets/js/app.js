import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {ConduktTerminal} from "./condukt_terminal.mjs"
import "./condukt_docs_shell.js"
// The home page still runs the WebAssembly terminal; it goes when the LiveView
// replaces it there.
import "./condukt_browser_agent.js"

const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")

const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: {ConduktTerminal},
})

liveSocket.connect()

window.liveSocket = liveSocket
