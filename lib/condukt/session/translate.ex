defmodule Condukt.Session.Translate do
  @moduledoc """
  Converts between Condukt's conversation types and ReqLLM's.

  This is the whole of Condukt's knowledge of what a provider request looks
  like, and it is the reason the rest of the session does not have to know. It
  lived inside `Condukt.Session` alongside the process, the agent loop, tool
  dispatch and persistence, where it was the largest block in the file and the
  one most obviously unrelated to running a GenServer.

  Every function here takes what it needs rather than a session struct, so
  nothing in this module can reach into session state and none of it needs a
  session to be tested.
  """

  alias Condukt.Message
  alias Condukt.Redactor
  alias ReqLLM.Message.ContentPart
  alias ReqLLM.ToolCall

  @doc """
  Builds the context sent to a provider.

  Redactors run on the way out, so nothing a redactor removes can reach the
  provider even though the session keeps it in history.
  """
  def context(messages, redactors, system_prompt) do
    context_messages =
      redactors
      |> Redactor.redact_messages(messages)
      |> Enum.map(&message_to_req_llm/1)
      |> List.flatten()

    if system_prompt do
      ReqLLM.Context.new([ReqLLM.Context.system(system_prompt) | context_messages])
    else
      ReqLLM.Context.new(context_messages)
    end
  end

  @doc "Translates a Condukt message into the shape ReqLLM expects."
  def message_to_req_llm(%Message{role: :user, content: content, images: []}) do
    ReqLLM.Context.user(content)
  end

  def message_to_req_llm(%Message{role: :user, content: content, images: images}) when images != [] do
    # ReqLLM represents multi-part user content as a list of content parts:
    # the text, then one image part per attachment as a base64 data URL.
    image_parts =
      Enum.map(images, fn image ->
        ContentPart.image_url("data:#{image.media_type};base64,#{image.data}")
      end)

    ReqLLM.Context.user([ContentPart.text(content) | image_parts])
  end

  def message_to_req_llm(%Message{role: :assistant, content: content}) when is_binary(content) do
    ReqLLM.Context.assistant(content)
  end

  def message_to_req_llm(%Message{role: :assistant, content: blocks}) when is_list(blocks) do
    text =
      blocks
      |> Enum.filter(&match?({:text, _}, &1))
      |> Enum.map_join("", fn {:text, chunk} -> chunk end)

    tool_calls =
      blocks
      |> Enum.filter(&match?({:tool_call, _, _, _}, &1))
      |> Enum.map(fn {:tool_call, id, name, arguments} ->
        %{id: id, name: name, arguments: arguments}
      end)

    if tool_calls == [] do
      ReqLLM.Context.assistant(text)
    else
      ReqLLM.Context.assistant(text, tool_calls: tool_calls)
    end
  end

  def message_to_req_llm(%Message{role: :tool_result, tool_call_id: id, content: content}) do
    ReqLLM.Context.tool_result(id, encode_tool_result(content))
  end

  defp encode_tool_result(content) when is_binary(content), do: content
  defp encode_tool_result({:error, reason}), do: "Error: #{inspect(reason)}"
  defp encode_tool_result(content), do: JSON.encode!(content)

  @doc """
  Turns a provider response into an assistant message.

  Thinking, text, and tool calls become ordered content blocks. A response with
  none of them still produces a message, because an empty assistant turn is
  part of the conversation and dropping it would leave the history unable to
  explain itself.
  """
  def response_to_message(response) do
    blocks =
      block(:thinking, ReqLLM.Response.thinking(response)) ++
        block(:text, ReqLLM.Response.text(response)) ++
        tool_call_blocks(response)

    if blocks == [], do: Message.assistant(""), else: Message.assistant(blocks)
  end

  defp block(_kind, nil), do: []
  defp block(_kind, ""), do: []
  defp block(kind, content), do: [{kind, content}]

  defp tool_call_blocks(response) do
    response
    |> ReqLLM.Response.tool_calls()
    |> Enum.map(fn call ->
      normalized = ToolCall.from_map(call)
      {:tool_call, normalized.id, normalized.name, normalized.arguments}
    end)
  end

  @doc """
  Builds the provider options for one call.

  `config` carries `:api_key`, `:base_url`, and `:thinking_level`; each is
  omitted when unset so a provider's own default applies.
  """
  def llm_opts(config, tools) do
    []
    |> put_present(:api_key, config[:api_key])
    |> put_present(:base_url, config[:base_url])
    |> put_tools(tools)
    |> put_reasoning(config[:thinking_level])
  end

  defp put_present(opts, _key, nil), do: opts
  defp put_present(opts, key, value), do: Keyword.put(opts, key, value)

  defp put_tools(opts, []), do: opts
  defp put_tools(opts, tools), do: Keyword.put(opts, :tools, tools)

  defp put_reasoning(opts, :off), do: Keyword.put(opts, :reasoning_effort, :none)

  defp put_reasoning(opts, level) when level in [:minimal, :low, :medium, :high] do
    Keyword.put(opts, :reasoning_effort, level)
  end

  defp put_reasoning(opts, _level), do: opts

  @doc """
  Normalizes a JSON Schema so its keys are strings.

  Schemas arrive written either way, and a provider that receives atom keys
  rejects the request rather than coercing them.
  """
  def normalize_json_schema(schema) when is_map(schema) do
    Map.new(schema, fn {key, value} -> {to_string(key), normalize_json_schema(value)} end)
  end

  def normalize_json_schema(schema) when is_list(schema), do: Enum.map(schema, &normalize_json_schema/1)
  def normalize_json_schema(value), do: value

  @doc "A model reference as a string, for telemetry metadata."
  def model_identifier(model) when is_binary(model), do: model
  def model_identifier(model), do: inspect(model)
end
