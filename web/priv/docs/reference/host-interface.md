# Host interface

The host interface is the provider-neutral boundary between Condukt's portable session and application-owned capabilities.

## Completion request

A completion request contains:

- `messages`: the complete conversation history required for the next model response.
- `tools`: the definitions registered by the current host.

Each tool definition has a unique `name`, a human-readable `description`, and a [JSON Schema](https://json-schema.org/) object describing its arguments.

## Starting a turn

`submit(prompt)` records a user message and returns the first completion request. A session rejects another submission while the current turn is waiting for inference or tool results.

## Receiving inference

`receive_completion(message)` accepts an assistant message and produces one of two results:

- `complete` contains the final assistant message.
- `run_tools` contains the assistant message and the requested tool calls.

The host must reject or translate provider responses that do not have the assistant role before passing them to the session.

## Returning tool outputs

`receive_tool_outputs(outputs)` requires exactly one output for every requested tool call. Each output contains:

| Field | Meaning |
| --- | --- |
| `toolCallId` | Identifier from the model's tool request |
| `content` | Text returned to the model |
| `isError` | Whether the tool failed |

The identifiers and order must match the outstanding calls. Condukt records the tool results and returns the next completion request.

## Host responsibilities

The host owns:

- provider credentials and model selection;
- network transport, retries, and request limits;
- tool argument validation and execution;
- cancellation and application lifecycle;
- presentation of messages and tool activity.

The portable session owns conversation history, state transitions, and validation that completion and tool results arrive in the expected order.
