defmodule Condukt.CLI.Credentials do
  @moduledoc """
  Credential persistence shared by the terminal, headless, and protocol hosts.

  The default directory follows the
  [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/latest/),
  and `CONDUKT_CREDENTIAL_DIR` lets harnesses select an isolated location.

  Writes go to a temporary file that is renamed over the credential, so a
  reader never observes a half-written key. Read-modify-write sequences take a
  directory lock first: `mkdir` is atomic on every platform Condukt targets, so
  two Condukt processes racing to import a credential cannot both win.
  """

  @credential_file "openrouter.key"
  @lock_directory ".credentials.lock"
  @lock_timeout 5_000
  @lock_retry 25

  defstruct [:directory]

  @doc """
  Builds a store rooted at `CONDUKT_CREDENTIAL_DIR`, falling back to the XDG
  configuration directory.
  """
  def from_environment(env \\ &System.get_env/1) do
    case env.("CONDUKT_CREDENTIAL_DIR") do
      directory when is_binary(directory) and directory != "" ->
        {:ok, new(directory)}

      _ ->
        with {:ok, config_home} <- xdg_config_home(env) do
          {:ok, new(Path.join(config_home, "condukt"))}
        end
    end
  end

  @doc "Builds a store rooted at an explicit directory."
  def new(directory), do: %__MODULE__{directory: directory}

  @doc "The directory this store reads and writes."
  def directory(%__MODULE__{directory: directory}), do: directory

  @doc """
  Reads the saved credential. Returns `{:ok, nil}` when none is saved.
  """
  def load(%__MODULE__{} = store) do
    with_lock(store, fn ->
      case File.read(credential_path(store)) do
        {:ok, credential} -> {:ok, credential}
        {:error, :enoent} -> {:ok, nil}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  @doc "Writes the credential, replacing any existing one."
  def save(%__MODULE__{} = store, credential) do
    with_lock(store, fn -> write_credential(store, credential) end)
  end

  @doc "Removes the saved credential. Succeeds when there is nothing to remove."
  def delete(%__MODULE__{} = store) do
    with_lock(store, fn ->
      case File.rm(credential_path(store)) do
        :ok -> :ok
        {:error, :enoent} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  @doc """
  Writes the credential only when the store is empty.

  Returns `{:ok, true}` when it wrote and `{:ok, false}` when a credential was
  already there.
  """
  def save_if_missing(%__MODULE__{} = store, credential) do
    with_lock(store, fn -> write_when_absent(store, credential) end)
  end

  defp write_when_absent(store, credential) do
    if File.exists?(credential_path(store)) do
      {:ok, false}
    else
      with :ok <- write_credential(store, credential), do: {:ok, true}
    end
  end

  @doc """
  Imports Pi's OpenRouter access credential without printing it.

  Returns `{:ok, true}` when an import happened and `{:ok, false}` when Condukt
  already has a credential. `CONDUKT_PI_AUTH_FILE` overrides the source path.
  """
  def import_pi_credential(env \\ &System.get_env/1) do
    with {:ok, store} <- from_environment(env),
         {:ok, source} <- pi_auth_file(env),
         {:ok, contents} <- read_pi_auth_file(source),
         {:ok, credential} <- pi_openrouter_access(contents) do
      save_if_missing(store, credential)
    end
  end

  defp read_pi_auth_file(source) do
    case File.read(source) do
      {:ok, contents} -> {:ok, contents}
      {:error, :enoent} -> {:error, {:pi_credential_missing, source}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp pi_auth_file(env) do
    case env.("CONDUKT_PI_AUTH_FILE") do
      path when is_binary(path) and path != "" ->
        {:ok, path}

      _ ->
        case env.("HOME") do
          home when is_binary(home) and home != "" ->
            {:ok, Path.join([home, ".pi", "agent", "auth.json"])}

          _ ->
            {:error, :pi_credential_path_unknown}
        end
    end
  end

  defp pi_openrouter_access(contents) do
    case JSON.decode(contents) do
      {:ok, %{"openrouter" => %{"access" => access}}} when is_binary(access) and access != "" ->
        {:ok, access}

      {:ok, _decoded} ->
        {:error, :pi_openrouter_credential_missing}

      {:error, _reason} ->
        {:error, :pi_credential_unreadable}
    end
  end

  defp credential_path(%__MODULE__{directory: directory}), do: Path.join(directory, @credential_file)

  defp write_credential(%__MODULE__{directory: directory} = store, credential) do
    temporary = Path.join(directory, ".#{@credential_file}.#{System.pid()}.tmp")

    with :ok <- File.write(temporary, credential),
         :ok <- set_private_permissions(temporary),
         :ok <- File.rename(temporary, credential_path(store)) do
      :ok
    else
      {:error, reason} ->
        File.rm(temporary)
        {:error, reason}
    end
  end

  defp with_lock(%__MODULE__{directory: directory} = store, operation) do
    with :ok <- File.mkdir_p(directory),
         :ok <- set_private_permissions(directory),
         :ok <- acquire_lock(store, @lock_timeout) do
      result = operation.()
      File.rmdir(lock_path(store))
      result
    end
  end

  defp lock_path(%__MODULE__{directory: directory}), do: Path.join(directory, @lock_directory)

  defp acquire_lock(store, remaining) do
    case File.mkdir(lock_path(store)) do
      :ok ->
        :ok

      {:error, :eexist} when remaining > 0 ->
        Process.sleep(@lock_retry)
        acquire_lock(store, remaining - @lock_retry)

      {:error, :eexist} ->
        # A crashed process can leave the directory behind. Taking it over is
        # safer than refusing every future write for the rest of the install.
        File.rmdir(lock_path(store))
        File.mkdir(lock_path(store))

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp set_private_permissions(path) do
    case :os.type() do
      {:unix, _flavour} -> File.chmod(path, 0o700)
      _other -> :ok
    end
  end

  defp xdg_config_home(env) do
    case env.("XDG_CONFIG_HOME") do
      path when is_binary(path) and path != "" ->
        {:ok, path}

      _ ->
        case env.("HOME") do
          home when is_binary(home) and home != "" -> {:ok, Path.join(home, ".config")}
          _ -> {:error, :home_directory_unknown}
        end
    end
  end
end
