defmodule Condukt.TestAgent do
  @moduledoc false
  use Condukt

  @impl true
  def tools, do: [Condukt.Tools.Bash]

  @impl true
  def system_prompt, do: "You are a helpful assistant. When asked to run a command, use the Bash tool. Be concise."

  @impl true
  def model, do: "zai:glm-4.5-flash"

  @impl true
  def thinking_level, do: :off
end
