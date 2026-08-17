defmodule ConduktSite.BrowserTools do
  @moduledoc """
  Tools that the agent calls on the server and the visitor's browser runs.

  The LiveView socket is open in both directions, so a tool does not have to
  execute where the loop does. The page declares what it can do when it
  connects, this turns each declaration into a `Condukt.Tool` whose `call/2`
  sends the invocation down the socket and waits for the answer, and the agent
  sees an ordinary tool.

  That split is what the demo is for. The loop is the real library, running
  server-side where sessions can outlive a tab, while the authority stays with
  the visitor: the tools reach GitHub from their browser, on their address,
  under whatever their page allows. Nothing the agent can do is borrowed from
  the server it runs on.

  ## Trusting the page

  The declarations arrive from the client, so they are treated as input rather
  than configuration: bounded in number and size, and dropped when malformed.
  There is nothing to escalate to. A tool call is only ever sent back to the
  same socket that declared it, and the result goes to the one agent waiting
  for it, so the worst a doctored client achieves is lying to its own agent.
  """

  require Logger

  @max_tools 16
  @max_name_bytes 64
  @max_description_bytes 4_000
  @call_timeout to_timeout(second: 30)

  @doc """
  Turns the page's declarations into tools bound to `page`.

  Malformed declarations are dropped rather than failing the batch: one bad
  entry from a client should cost that tool, not the conversation.
  """
  def build(declarations, page) when is_list(declarations) do
    declarations
    |> Enum.take(@max_tools)
    |> Enum.flat_map(&build_one(&1, page))
  end

  def build(_declarations, _page), do: []

  defp build_one(
         %{"name" => name, "description" => description, "parameters" => parameters},
         page
       )
       when is_binary(name) and is_binary(description) and is_map(parameters) do
    if valid_name?(name) and byte_size(description) <= @max_description_bytes do
      [
        Condukt.tool(
          name: name,
          description: description,
          parameters: parameters,
          call: fn args, _context -> call(page, name, args) end
        )
      ]
    else
      Logger.debug("browser tool declaration refused: #{inspect(name)}")
      []
    end
  end

  defp build_one(_declaration, _page), do: []

  # Tool names reach the model and come back as identifiers, so the shape is
  # restricted to what a provider will accept rather than passed through.
  defp valid_name?(name) do
    byte_size(name) in 1..@max_name_bytes and name =~ ~r/^[a-zA-Z0-9_-]+$/
  end

  @doc """
  Invokes a tool in the browser and waits for the result.

  Runs in the process executing the tool, which the session has already placed
  outside itself, so blocking here holds up the one turn that is waiting and
  nothing else.
  """
  def call(page, name, args) do
    monitor = Process.monitor(page)
    ref = make_ref()

    send(page, {:browser_tool, self(), ref, name, args})

    receive do
      {:browser_tool_result, ^ref, result} ->
        Process.demonitor(monitor, [:flush])
        result

      # A closed tab should end the tool now rather than at the timeout: the
      # answer is never coming, and the turn is still holding a slot.
      {:DOWN, ^monitor, :process, ^page, _reason} ->
        {:error, "the page closed before #{name} finished"}
    after
      @call_timeout ->
        Process.demonitor(monitor, [:flush])
        {:error, "the browser did not answer #{name} within #{div(@call_timeout, 1000)} seconds"}
    end
  end

  @doc "How long a browser tool is given to answer."
  def call_timeout, do: @call_timeout

  @doc "The most tools a page may declare."
  def max_tools, do: @max_tools
end
