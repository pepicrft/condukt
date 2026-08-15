import Config

# The default handler writes to the same terminal the interface draws on, and
# to the same standard output the protocol server uses for JSON-RPC frames. A
# single log line corrupts either one: on the interface it scrolls the screen
# out from under the renderer, so every later redraw lands a row off; in the
# protocol server it is read by the editor as a malformed message.
#
# Nothing in the agent relies on console logging. Attach a file handler if a
# session ever needs tracing.
config :logger, :default_handler, false
