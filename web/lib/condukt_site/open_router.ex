defmodule ConduktSite.OpenRouter do
  @moduledoc """
  OpenRouter authorization and inference owned by the web host.

  The browser-facing Condukt package never sees the credential. It sends a
  provider-neutral completion request to the application, which is translated
  here and authenticated with the encrypted session credential.
  """

  @authorize_url "https://openrouter.ai/auth"
  @key_url "https://openrouter.ai/api/v1/auth/keys"
  @completion_url "https://openrouter.ai/api/v1/chat/completions"

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

  @doc "Complete one provider-neutral agent request using an OpenRouter key."
  def complete(key, params) do
    body = completion_body(params)

    request(
      :post,
      @completion_url,
      headers: [
        {"authorization", "Bearer #{key}"},
        {"http-referer", ConduktSiteWeb.Endpoint.url()},
        {"x-openrouter-title", "Condukt"}
      ],
      json: body
    )
    |> case do
      {:ok, %{status: status, body: response}} when status in 200..299 ->
        decode_completion(response)

      {:ok, response} ->
        {:error, response.status, response_error(response)}

      {:error, error} ->
        {:error, 502, "Could not reach OpenRouter: #{Exception.message(error)}"}
    end
  end

  @doc false
  def completion_body(params) do
    model = params["model"] || Application.fetch_env!(:condukt_site, :openrouter_model)
    messages = Enum.map(params["messages"] || [], &encode_message/1)
    tools = Enum.map(params["tools"] || [], &encode_tool/1)

    %{
      "model" => model,
      "messages" => messages,
      "reasoning" => %{"effort" => "high", "exclude" => true}
    }
    |> then(fn body -> if tools == [], do: body, else: Map.put(body, "tools", tools) end)
  end

  defp encode_message(message) do
    %{
      "role" => message["role"],
      "content" => message["content"] || ""
    }
    |> maybe_put("tool_call_id", message["toolCallId"])
    |> maybe_put(
      "tool_calls",
      case message["toolCalls"] do
        calls when is_list(calls) -> Enum.map(calls, &encode_tool_call/1)
        _ -> nil
      end
    )
  end

  defp encode_tool_call(call) do
    %{
      "id" => call["id"],
      "type" => "function",
      "function" => %{
        "name" => call["name"],
        "arguments" => call["arguments"] || "{}"
      }
    }
  end

  defp encode_tool(tool) do
    %{
      "type" => "function",
      "function" => %{
        "name" => tool["name"],
        "description" => tool["description"] || "",
        "parameters" => tool["parameters"] || %{"type" => "object", "properties" => %{}}
      }
    }
  end

  defp decode_completion(%{"choices" => [%{"message" => message} | _]}) when is_map(message) do
    with {:ok, content} <- decode_content(message["content"]),
         {:ok, calls} <- decode_tool_calls(message["tool_calls"] || []) do
      result = %{"role" => "assistant", "content" => content}
      {:ok, if(calls == [], do: result, else: Map.put(result, "toolCalls", calls))}
    else
      :error -> {:error, 502, "OpenRouter returned an invalid response"}
    end
  end

  defp decode_completion(_response), do: {:error, 502, "OpenRouter returned an invalid response"}

  defp request(method, url, options) do
    defaults = Application.get_env(:condukt_site, :openrouter_request_options, [])
    Req.request(Keyword.merge(defaults, [method: method, url: url] ++ options))
  end

  defp decode_content(nil), do: {:ok, ""}
  defp decode_content(content) when is_binary(content), do: {:ok, content}

  defp decode_content(content) when is_list(content) do
    text =
      content
      |> Enum.flat_map(fn
        %{"text" => text} when is_binary(text) -> [text]
        text when is_binary(text) -> [text]
        _part -> []
      end)
      |> Enum.join("\n")

    if text == "", do: :error, else: {:ok, text}
  end

  defp decode_content(_content), do: :error

  defp decode_tool_calls(calls) when is_list(calls) do
    Enum.reduce_while(calls, {:ok, []}, fn
      %{"id" => id, "function" => %{"name" => name} = function}, {:ok, decoded}
      when is_binary(id) and id != "" and is_binary(name) and name != "" ->
        arguments = function["arguments"] || "{}"

        case encode_arguments(arguments) do
          {:ok, arguments} ->
            call = %{"id" => id, "name" => name, "arguments" => arguments}
            {:cont, {:ok, [call | decoded]}}

          :error ->
            {:halt, :error}
        end

      _call, _decoded ->
        {:halt, :error}
    end)
    |> case do
      {:ok, decoded} -> {:ok, Enum.reverse(decoded)}
      :error -> :error
    end
  end

  defp decode_tool_calls(_calls), do: :error

  defp encode_arguments(arguments) when is_binary(arguments), do: {:ok, arguments}

  defp encode_arguments(arguments) when is_map(arguments) do
    case Jason.encode(arguments) do
      {:ok, encoded} -> {:ok, encoded}
      {:error, _reason} -> :error
    end
  end

  defp encode_arguments(_arguments), do: :error

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

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp random_url_string(byte_count) do
    byte_count
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
