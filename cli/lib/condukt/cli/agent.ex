defmodule Condukt.CLI.Agent do
  @moduledoc """
  The coding agent every Condukt host runs.

  The terminal interface, `condukt exec`, and the Agent Client Protocol server
  all start a session from this module, so a task behaves the same whichever
  surface asked for it. Everything below the interface (the turn loop, tool
  dispatch, sandboxing, retries, telemetry) comes from the Condukt library.
  """

  use Condukt.Agent

  alias Condukt.CLI.AgentPrompt
  alias Condukt.CLI.OpenRouter

  @impl Condukt
  def model, do: OpenRouter.req_llm_model()

  @impl Condukt
  def system_prompt, do: AgentPrompt.coding_agent()

  @impl Condukt
  def thinking_level, do: :high

  @impl Condukt
  def tools, do: [Condukt.Tools.Read, Condukt.Tools.Bash]
end
