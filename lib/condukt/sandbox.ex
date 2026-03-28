defmodule Condukt.Sandbox do
  @moduledoc """
  Manages sandbox environments for remote agent execution.

  When a sandbox is configured, the local agent acts as a client/frontend while
  tool execution happens in a remote sandbox environment. The sandbox is provisioned
  via Terrarium, and the current BEAM runtime is replicated into it using
  `Terrarium.replicate/2` — which installs the same OTP version (via mise),
  deploys the running code, and starts a connected peer node over SSH.

  Tool calls are then executed on the remote node via `:erpc`.

  ## Configuration

  Agents declare sandbox support by implementing the `sandbox/0` callback:

      defmodule MyAgent do
        use Condukt

        @impl true
        def sandbox do
          %{
            provider: Terrarium.Providers.Exe,
            provider_opts: [token: System.fetch_env!("EXE_DEV_TOKEN")]
          }
        end
      end

  Or pass `:sandbox` as an option to `start_link/1`:

      MyAgent.start_link(sandbox: %{
        provider: Terrarium.Providers.Exe,
        provider_opts: [token: System.fetch_env!("EXE_DEV_TOKEN")]
      })
  """

  use GenServer

  require Logger

  defstruct [:terrarium_sandbox, :peer_pid, :node]

  @type t :: %__MODULE__{
          terrarium_sandbox: Terrarium.Sandbox.t() | nil,
          peer_pid: pid() | nil,
          node: node() | nil
        }

  @type config :: %{
          required(:provider) => module(),
          optional(:provider_opts) => keyword()
        }

  @doc """
  Starts a sandbox process that provisions the remote environment.
  """
  @spec start_link(config()) :: GenServer.on_start()
  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end

  @doc """
  Stops the sandbox, tearing down the peer node and destroying the remote environment.
  """
  @spec stop(GenServer.server()) :: :ok
  def stop(pid) do
    GenServer.stop(pid)
  end

  @doc """
  Returns the remote node name.
  """
  @spec remote_node(GenServer.server()) :: node()
  def remote_node(pid) do
    GenServer.call(pid, :remote_node)
  end

  @doc """
  Executes a tool on the remote sandbox node.

  The tool module, arguments, and context are sent to the remote node
  and executed there via `:erpc.call/4`.
  """
  @spec exec_tool(GenServer.server(), module() | {module(), keyword()}, map(), Condukt.Tool.context()) ::
          Condukt.Tool.result()
  def exec_tool(pid, tool_spec, args, context) do
    GenServer.call(pid, {:exec_tool, tool_spec, args, context}, :infinity)
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(config) do
    case provision(config) do
      {:ok, state} ->
        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def terminate(_reason, state) do
    if state.peer_pid do
      Logger.debug("Stopping sandbox peer node", node: state.node)
      Terrarium.stop_replica(state.peer_pid)
    end

    if state.terrarium_sandbox do
      Logger.info("Destroying sandbox", sandbox_id: state.terrarium_sandbox.id)
      Terrarium.destroy(state.terrarium_sandbox)
    end

    :ok
  end

  @impl true
  def handle_call(:remote_node, _from, state) do
    {:reply, state.node, state}
  end

  def handle_call({:exec_tool, tool_spec, args, context}, _from, state) do
    # Use :peer.call instead of :erpc.call because :standard_io peer connections
    # don't use Erlang distribution — :erpc requires distribution and fails with :noconnection.
    result = :peer.call(state.peer_pid, Condukt.Tool, :execute, [tool_spec, args, context])
    {:reply, result, state}
  catch
    kind, reason ->
      {:reply, {:error, {kind, reason}}, state}
  end

  # ============================================================================
  # Provisioning
  # ============================================================================

  defp provision(config) do
    provider = Map.fetch!(config, :provider)
    provider_opts = Map.get(config, :provider_opts, [])

    with {:ok, sandbox} <- Terrarium.create(provider, provider_opts),
         {:ok, peer_pid, node} <- Terrarium.replicate(sandbox) do
      Logger.info("Sandbox provisioned",
        sandbox_id: sandbox.id,
        node: node,
        provider: provider
      )

      {:ok,
       %__MODULE__{
         terrarium_sandbox: sandbox,
         peer_pid: peer_pid,
         node: node
       }}
    else
      {:error, reason} ->
        Logger.error("Failed to provision sandbox", reason: inspect(reason))
        {:error, reason}
    end
  end
end
