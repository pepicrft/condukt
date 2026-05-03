defmodule Condukt.Tools.Subagent do
  @moduledoc """
  Tool for delegating a task to a registered sub-agent role.

  This tool is injected automatically when an agent declares `subagents/0`.
  It starts a fresh child `Condukt.Session`, runs the task once, returns the
  child's final response, and terminates the child session.
  """

  use Condukt.Tool

  @impl true
  def name, do: "subagent"

  @impl true
  def name(_opts), do: name()

  @impl true
  def description do
    "Delegate a task to one of the registered sub-agent roles."
  end

  @impl true
  def description(_opts), do: description()

  @impl true
  def parameters(opts) do
    roles =
      opts
      |> Keyword.get(:subagents, [])
      |> Enum.map(fn {role, _registration} -> Atom.to_string(role) end)

    %{
      type: "object",
      properties: %{
        role: %{
          type: "string",
          enum: roles,
          description: "Registered sub-agent role to run."
        },
        task: %{
          type: "string",
          description: "What the sub-agent should do."
        }
      },
      required: ["role", "task"]
    }
  end

  @impl true
  def call(args, context) do
    role = Map.get(args, "role") || Map.get(args, :role)
    task = Map.get(args, "task") || Map.get(args, :task)

    with {:ok, {agent_module, opts}} <- lookup(context, role),
         {:ok, supervisor} <- fetch_supervisor(context),
         child_opts = inherit(opts, context),
         {:ok, child} <- start_child(supervisor, agent_module, child_opts) do
      run_and_stop(supervisor, child, task)
    end
  end

  defp lookup(context, role) when is_binary(role) do
    context
    |> subagents()
    |> Enum.find(fn {registered_role, _registration} -> Atom.to_string(registered_role) == role end)
    |> case do
      nil -> {:error, "no sub-agent registered as #{role}"}
      {_role, registration} -> normalize_registration(registration)
    end
  end

  defp lookup(_context, role), do: {:error, "no sub-agent registered as #{inspect(role)}"}

  defp normalize_registration(module) when is_atom(module), do: {:ok, {module, []}}

  defp normalize_registration({module, opts}) when is_atom(module) and is_list(opts) do
    {:ok, {module, opts}}
  end

  defp normalize_registration(registration), do: {:error, {:invalid_subagent_registration, registration}}

  defp subagents(context) do
    context
    |> Map.get(:opts, [])
    |> Keyword.get(:subagents, Map.get(context, :subagents, []))
  end

  defp fetch_supervisor(%{subagent_supervisor: supervisor}) when is_pid(supervisor), do: {:ok, supervisor}
  defp fetch_supervisor(_context), do: {:error, :subagent_supervisor_unavailable}

  defp inherit(opts, context) do
    opts
    |> Keyword.put_new(:sandbox, Map.fetch!(context, :sandbox))
    |> Keyword.put_new(:cwd, Map.fetch!(context, :cwd))
    |> put_new_present(:api_key, Map.get(context, :api_key))
  end

  defp put_new_present(opts, _key, nil), do: opts
  defp put_new_present(opts, key, value), do: Keyword.put_new(opts, key, value)

  defp start_child(supervisor, agent_module, opts) do
    child_spec = %{
      id: {__MODULE__, make_ref()},
      start: {Condukt.Session, :start_link, [agent_module, opts]},
      restart: :temporary,
      type: :worker
    }

    case DynamicSupervisor.start_child(supervisor, child_spec) do
      {:ok, pid} -> {:ok, pid}
      {:ok, pid, _info} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_and_stop(supervisor, child, task) do
    Condukt.run(child, task)
  catch
    :exit, reason -> {:error, reason}
  after
    terminate_child(supervisor, child)
  end

  defp terminate_child(supervisor, child) do
    if Process.alive?(child) do
      _ = DynamicSupervisor.terminate_child(supervisor, child)
    end

    :ok
  end
end
