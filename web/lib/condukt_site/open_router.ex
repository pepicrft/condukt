defmodule ConduktSite.OpenRouter do
  @moduledoc """
  OpenRouter sign-in on behalf of a visitor.

  Proof Key for Code Exchange, so the application never holds a provider
  credential of its own: the visitor authorizes a key, it is stored in the
  encrypted session, and inference is billed to them.

  Inference itself is not here any more. The terminal's agent is a
  `Condukt.Session` that talks to OpenRouter through ReqLLM with that key, so
  the completion proxy this module used to carry, which existed only to keep
  the credential away from the WebAssembly agent in the page, went with it.
  """

  @authorize_url "https://openrouter.ai/auth"
  @key_url "https://openrouter.ai/api/v1/auth/keys"

  defmodule Authorization do
    @moduledoc false
    defstruct [:state, :verifier, :url]
  end

  @doc "Build a fresh Proof Key for Code Exchange authorization request."
  def authorization(callback_url) do
    state = random_url_string(24)
    verifier = random_url_string(64)
    challenge = :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)

    query =
      URI.encode_query(%{
        "callback_url" => callback_url.(state),
        "code_challenge" => challenge,
        "code_challenge_method" => "S256"
      })

    %Authorization{state: state, verifier: verifier, url: @authorize_url <> "?" <> query}
  end

  @doc "Exchange an OpenRouter authorization code for a user-controlled key."
  def exchange_code(code, verifier) do
    request(
      :post,
      @key_url,
      json: %{
        code: code,
        code_verifier: verifier,
        code_challenge_method: "S256"
      }
    )
    |> case do
      {:ok, %{status: status, body: %{"key" => key}}}
      when status in 200..299 and is_binary(key) and key != "" ->
        {:ok, key}

      {:ok, response} ->
        {:error, response_error(response)}

      {:error, error} ->
        {:error, "Could not reach OpenRouter: #{Exception.message(error)}"}
    end
  end

  defp request(method, url, options) do
    defaults = Application.get_env(:condukt_site, :openrouter_request_options, [])
    Req.request(Keyword.merge(defaults, [method: method, url: url] ++ options))
  end

  defp response_error(%{status: status, body: body}) when is_map(body) do
    detail = response_detail(body)

    "OpenRouter returned status #{status}: #{detail}"
  end

  defp response_error(%{status: status}), do: "OpenRouter returned status #{status}"

  defp response_detail(%{"error" => %{"message" => message}}) when is_binary(message),
    do: message

  defp response_detail(%{"message" => message}) when is_binary(message), do: message
  defp response_detail(%{"error" => error}) when is_binary(error), do: error
  defp response_detail(_body), do: "request failed"

  defp random_url_string(byte_count) do
    byte_count
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
