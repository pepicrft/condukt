defmodule Condukt.CLI.OpenRouter do
  @moduledoc """
  OpenRouter connection details: the model the terminal agent runs, credential
  persistence, and the check that a key still authenticates.

  Inference itself goes through `ReqLLM` inside `Condukt.Session`; this module
  only owns the parts of the provider relationship that live outside a turn.
  """

  alias Condukt.CLI.Credentials

  @default_model "minimax/minimax-m3"
  @base_url "https://openrouter.ai/api/v1"
  # End-to-end timeout for every OpenRouter call made here. Validation usually
  # returns in well under a second; 30s is generous but still bounded so a hung
  # connection cannot freeze the agent.
  @request_timeout 30_000

  @doc "Provider name shown in the interface."
  def provider_name, do: "OpenRouter"

  @doc "The OpenRouter model identifier the terminal agent runs."
  def model, do: @default_model

  @doc "The ReqLLM model specification for `Condukt.Session`."
  def req_llm_model, do: "openrouter:" <> @default_model

  @doc "The page where a user can create or copy an API key."
  def keys_url, do: "https://openrouter.ai/keys"

  @doc "Default OpenRouter API base URL. Overridable so tests can point at a local server."
  def base_url, do: @base_url

  @doc """
  Reads the saved key.

  Returns `{:ok, key}`, `{:ok, nil}` when nothing is saved, or `{:error, reason}`.
  """
  def load_key(env \\ &System.get_env/1) do
    with {:ok, store} <- Credentials.from_environment(env), do: Credentials.load(store)
  end

  @doc "Writes the key to the credential store."
  def save_key(key, env \\ &System.get_env/1) do
    with {:ok, store} <- Credentials.from_environment(env), do: Credentials.save(store, key)
  end

  @doc "Removes the saved key so the next `/connect` starts from a clean slate."
  def delete_key(env \\ &System.get_env/1) do
    with {:ok, store} <- Credentials.from_environment(env), do: Credentials.delete(store)
  end

  @doc """
  Confirms the key authenticates against `/auth/key`.

  Used right after saving so Condukt never reports a working connection that
  OpenRouter would reject on the first real request. Returns `:ok` or
  `{:error, message}` with text meant for the user.

  ## Options

    * `:base_url` - API base URL, for pointing tests at a local server
    * `:receive_timeout` - request timeout in milliseconds
  """
  def validate(key, opts \\ []) do
    url = Keyword.get(opts, :base_url, @base_url) <> "/auth/key"
    timeout = Keyword.get(opts, :receive_timeout, @request_timeout)

    [url: url, auth: {:bearer, key}, receive_timeout: timeout, retry: false]
    |> Req.new()
    |> Req.get()
    |> interpret_validation()
  end

  defp interpret_validation({:ok, %Req.Response{status: status}}) when status in 200..299, do: :ok

  defp interpret_validation({:ok, %Req.Response{status: 401}}) do
    {:error, "The saved OpenRouter key is no longer valid. Run /connect to re-authenticate."}
  end

  defp interpret_validation({:ok, %Req.Response{status: status}}) do
    {:error, "OpenRouter returned HTTP #{status} while validating the key."}
  end

  defp interpret_validation({:error, reason}) do
    {:error, "Could not reach OpenRouter to validate the key: #{describe(reason)}"}
  end

  @doc """
  Turns a failed turn into a message a user can act on.

  A 401 in particular usually means the saved key was revoked or never worked.
  """
  def describe_turn_error(reason) do
    text = describe(reason)

    cond do
      String.contains?(text, "401") ->
        "OpenRouter rejected the saved key. Run /connect to re-authenticate."

      String.contains?(text, "timeout") ->
        "OpenRouter request timed out."

      true ->
        text
    end
  end

  defp describe(%{__exception__: true} = exception), do: Exception.message(exception)
  defp describe(reason) when is_binary(reason), do: reason
  defp describe(reason), do: inspect(reason)
end
