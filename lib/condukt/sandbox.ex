defmodule Condukt.Sandbox do
  @moduledoc """
  Manages sandbox environments for remote agent execution.

  When a sandbox is configured, the local agent acts as a client/frontend while
  tool execution happens in a remote sandbox environment. The transport between
  local and remote uses SSH, with Erlang's `:peer` module establishing a remote
  BEAM node over a `:standard_io` connection tunneled through SSH.

  ## Architecture

  1. A sandbox is provisioned via Terrarium (provider-agnostic)
  2. The same Erlang/OTP version is deployed to the sandbox
  3. The application's BEAM files are copied to the sandbox
  4. A remote BEAM node is started via `:peer` over SSH (`:standard_io`)
  5. Tool calls are executed on the remote node via `:erpc`
  6. On shutdown, the peer node is stopped and the sandbox is destroyed

  ## Configuration

  Agents declare sandbox support by implementing the `sandbox/0` callback:

      defmodule MyAgent do
        use Condukt

        @impl true
        def sandbox do
          %{
            provider: Terrarium.Providers.Daytona,
            provider_opts: [api_key: System.fetch_env!("DAYTONA_API_KEY")]
          }
        end
      end

  Or pass `:sandbox` as an option to `start_link/1`:

      MyAgent.start_link(sandbox: %{
        provider: Terrarium.Providers.Daytona,
        provider_opts: [api_key: System.fetch_env!("DAYTONA_API_KEY")]
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
          optional(:provider_opts) => keyword(),
          optional(:terrarium_config) => keyword()
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
      :peer.stop(state.peer_pid)
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
    # Execute the tool on the remote node via Erlang RPC
    result = :erpc.call(state.node, Condukt.Tool, :execute, [tool_spec, args, context])
    {:reply, result, state}
  rescue
    error ->
      {:reply, {:error, Exception.message(error)}, state}
  end

  # ============================================================================
  # Provisioning Pipeline
  # ============================================================================

  defp provision(config) do
    provider = Map.fetch!(config, :provider)
    provider_opts = Map.get(config, :provider_opts, [])
    terrarium_config = Map.get(config, :terrarium_config)

    create_opts = if terrarium_config, do: Keyword.put(provider_opts, :config, terrarium_config), else: provider_opts

    with {:ok, sandbox} <- Terrarium.create(provider, create_opts),
         {:ok, ssh} <- Terrarium.ssh_opts(sandbox),
         :ok <- deploy_runtime(sandbox),
         {:ok, peer_pid, node} <- start_peer(sandbox, ssh) do
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

  # ============================================================================
  # Runtime Deployment
  # ============================================================================

  defp deploy_runtime(sandbox) do
    otp_release = :erlang.system_info(:otp_release) |> List.to_string()
    Logger.info("Deploying runtime to sandbox", sandbox_id: sandbox.id, otp_release: otp_release)

    with :ok <- install_erlang(sandbox, otp_release) do
      copy_beam_files(sandbox)
    end
  end

  defp install_erlang(sandbox, otp_version) do
    # Check if matching Erlang is already installed, otherwise install it.
    # Supports mise, apt-get, and apk package managers.
    install_script = """
    #!/bin/bash
    set -e

    if command -v erl &> /dev/null; then
      installed=$(erl -eval 'io:format("~s", [erlang:system_info(otp_release)]), halt().' -noshell)
      if [ "$installed" = "#{otp_version}" ]; then
        exit 0
      fi
    fi

    if command -v mise &> /dev/null; then
      mise install erlang #{otp_version}
      mise use -g erlang #{otp_version}
    elif command -v apt-get &> /dev/null; then
      apt-get update -qq && apt-get install -y -qq erlang-nox > /dev/null 2>&1
    elif command -v apk &> /dev/null; then
      apk add --no-cache erlang > /dev/null 2>&1
    else
      echo "No supported package manager found to install Erlang" >&2
      exit 1
    fi
    """

    case Terrarium.exec(sandbox, install_script, timeout: 300_000) do
      {:ok, %{exit_code: 0}} ->
        :ok

      {:ok, result} ->
        {:error, {:erlang_install_failed, result.exit_code, result.stderr}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp copy_beam_files(sandbox) do
    root_dir = :code.root_dir() |> List.to_string()
    tar_path = Path.join(System.tmp_dir!(), "condukt_deploy_#{System.unique_integer([:positive])}.tar.gz")

    try do
      # Create a tarball of the Erlang lib directory (contains all BEAM files)
      case System.cmd("tar", ["-czf", tar_path, "-C", root_dir, "lib"], stderr_to_stdout: true) do
        {_, 0} ->
          content = File.read!(tar_path)

          with :ok <- Terrarium.write_file(sandbox, "/opt/condukt/release.tar.gz", content),
               {:ok, %{exit_code: 0}} <-
                 Terrarium.exec(
                   sandbox,
                   "mkdir -p /opt/condukt && cd /opt/condukt && tar -xzf release.tar.gz && rm release.tar.gz"
                 ) do
            :ok
          else
            {:ok, result} -> {:error, {:deploy_extract_failed, result.exit_code, result.stderr}}
            {:error, reason} -> {:error, reason}
          end

        {output, code} ->
          {:error, {:tar_failed, code, output}}
      end
    after
      File.rm(tar_path)
    end
  end

  # ============================================================================
  # Peer Node (SSH Transport)
  # ============================================================================

  defp start_peer(sandbox, ssh_opts) do
    ssh_cmd = build_ssh_command(ssh_opts)
    erl_cmd = build_erl_command()
    exec = ~c"#{ssh_cmd} '#{erl_cmd}'"

    node_name = :"condukt_sandbox_#{sandbox.id}"

    Logger.debug("Starting peer node via SSH",
      sandbox_id: sandbox.id,
      node_name: node_name
    )

    case :peer.start(%{
           name: node_name,
           connection: :standard_io,
           exec: exec
         }) do
      {:ok, peer_pid, node} ->
        Logger.info("Peer node started", node: node, sandbox_id: sandbox.id)
        {:ok, peer_pid, node}

      {:error, reason} ->
        {:error, {:peer_start_failed, reason}}
    end
  end

  defp build_ssh_command(ssh_opts) do
    host = ssh_opts[:host]
    port = ssh_opts[:port] || 22
    user = ssh_opts[:user]
    auth = ssh_opts[:auth]

    parts = [
      "ssh",
      "-o StrictHostKeyChecking=no",
      "-o UserKnownHostsFile=/dev/null",
      "-p #{port}"
    ]

    parts = add_auth_opts(parts, auth)

    Enum.join(parts ++ ["#{user}@#{host}"], " ")
  end

  defp add_auth_opts(parts, {:key_path, path}) do
    parts ++ ["-i #{path}"]
  end

  defp add_auth_opts(parts, {:key, pem}) do
    # Write PEM key to a temp file for SSH CLI usage
    tmp_path = Path.join(System.tmp_dir!(), ".condukt_ssh_key_#{System.unique_integer([:positive])}")
    File.write!(tmp_path, pem)
    File.chmod!(tmp_path, 0o600)
    parts ++ ["-i #{tmp_path}"]
  end

  defp add_auth_opts(parts, {:user_dir, dir}) do
    # Let SSH discover keys from the specified directory
    parts ++ ["-o IdentityFile=#{dir}/id_ed25519", "-o IdentityFile=#{dir}/id_rsa"]
  end

  defp add_auth_opts(parts, _) do
    # nil or unsupported — rely on default SSH key discovery
    parts
  end

  defp build_erl_command do
    pa_paths = "/opt/condukt/lib/*/ebin"
    "erl -noinput -pa #{pa_paths}"
  end
end
