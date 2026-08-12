defmodule ConduktSite.CompletionRequest do
  @moduledoc """
  Validates the provider-neutral completion boundary exposed to the browser.

  The page owns inference configuration, but it cannot send unbounded or
  structurally invalid history and tool definitions through the proxy.
  """

  @max_encoded_bytes 512 * 1024
  @max_messages 128
  @max_tools 32
  @max_tool_calls 32
  @max_content_bytes 64 * 1024
  @max_identifier_bytes 200

  def validate(params) when is_map(params) do
    with :ok <- validate_size(params),
         :ok <- validate_model(params["model"]),
         :ok <- validate_messages(params["messages"]),
         :ok <- validate_tools(params["tools"] || []) do
      {:ok, params}
    end
  end

  def validate(_params), do: invalid("expected a JSON object")

  defp validate_size(params) do
    case Jason.encode(params) do
      {:ok, encoded} when byte_size(encoded) <= @max_encoded_bytes -> :ok
      {:ok, _encoded} -> invalid("request is larger than 512 kilobytes")
      {:error, _reason} -> invalid("request cannot be encoded")
    end
  end

  defp validate_model(nil), do: :ok
  defp validate_model(model), do: required_string(model, "model", @max_identifier_bytes)

  defp validate_messages(messages) when is_list(messages) do
    cond do
      messages == [] -> invalid("messages cannot be empty")
      length(messages) > @max_messages -> invalid("too many messages")
      true -> validate_each(messages, &validate_message/1)
    end
  end

  defp validate_messages(_messages), do: invalid("messages must be a list")

  defp validate_message(%{"role" => role} = message)
       when role in ["system", "user", "assistant", "tool"] do
    with :ok <- optional_string(message["content"], "message content", @max_content_bytes),
         :ok <- validate_tool_call_id(role, message["toolCallId"]),
         :ok <- validate_tool_calls(message["toolCalls"]) do
      :ok
    end
  end

  defp validate_message(_message), do: invalid("every message needs a supported role")

  defp validate_tool_call_id("tool", id),
    do: required_string(id, "toolCallId", @max_identifier_bytes)

  defp validate_tool_call_id(_role, nil), do: :ok

  defp validate_tool_call_id(_role, id),
    do: required_string(id, "toolCallId", @max_identifier_bytes)

  defp validate_tool_calls(nil), do: :ok

  defp validate_tool_calls(calls) when is_list(calls) do
    if length(calls) <= @max_tool_calls do
      validate_each(calls, &validate_tool_call/1)
    else
      invalid("too many tool calls in one message")
    end
  end

  defp validate_tool_calls(_calls), do: invalid("toolCalls must be a list")

  defp validate_tool_call(%{"id" => id, "name" => name, "arguments" => arguments}) do
    with :ok <- required_string(id, "tool call id", @max_identifier_bytes),
         :ok <- required_string(name, "tool call name", @max_identifier_bytes),
         :ok <- optional_string(arguments, "tool call arguments", @max_content_bytes) do
      :ok
    end
  end

  defp validate_tool_call(_call), do: invalid("tool calls need id, name, and arguments")

  defp validate_tools(tools) when is_list(tools) do
    if length(tools) <= @max_tools do
      validate_each(tools, &validate_tool/1)
    else
      invalid("too many tools")
    end
  end

  defp validate_tools(_tools), do: invalid("tools must be a list")

  defp validate_tool(%{"name" => name, "parameters" => parameters} = tool)
       when is_map(parameters) do
    with :ok <- required_string(name, "tool name", @max_identifier_bytes),
         :ok <- optional_string(tool["description"], "tool description", @max_content_bytes) do
      :ok
    end
  end

  defp validate_tool(_tool), do: invalid("tools need a name and object parameters")

  defp validate_each(values, validator) do
    Enum.reduce_while(values, :ok, fn value, :ok ->
      case validator.(value) do
        :ok -> {:cont, :ok}
        {:error, _message} = error -> {:halt, error}
      end
    end)
  end

  defp optional_string(nil, _field, _limit), do: :ok
  defp optional_string(value, field, limit), do: bounded_string(value, field, limit, true)
  defp required_string(value, field, limit), do: bounded_string(value, field, limit, false)

  defp bounded_string(value, field, limit, allow_empty) when is_binary(value) do
    cond do
      not allow_empty and value == "" -> invalid("#{field} cannot be empty")
      byte_size(value) > limit -> invalid("#{field} is too long")
      true -> :ok
    end
  end

  defp bounded_string(_value, field, _limit, _allow_empty),
    do: invalid("#{field} must be a string")

  defp invalid(detail), do: {:error, "Invalid completion request: #{detail}."}
end
