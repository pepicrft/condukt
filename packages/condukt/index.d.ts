export type JsonSchema = Record<string, unknown>

export interface ToolDefinition {
  name: string
  description: string
  parameters: JsonSchema
}

export interface ToolCall {
  id: string
  name: string
  arguments: string
}

export interface Message {
  role: "system" | "user" | "assistant" | "tool"
  content: string
  toolCalls?: ToolCall[]
  toolCallId?: string
}

export interface CompletionRequest {
  messages: Message[]
  tools: ToolDefinition[]
}

export interface Inference {
  complete(
    request: CompletionRequest,
    context?: {signal?: AbortSignal},
  ): Promise<Message>
}

export interface Tool<TArguments = Record<string, unknown>, TResult = unknown>
  extends ToolDefinition {
  execute(
    arguments: TArguments,
    context: {signal?: AbortSignal; call: ToolCall},
  ): TResult | Promise<TResult>
}

export type AgentEvent =
  | {type: "assistant_message"; message: Message}
  | {type: "tool_call"; call: ToolCall}
  | {
      type: "tool_result"
      call: ToolCall
      output: {toolCallId: string; content: string; isError: boolean}
    }
  | {type: "complete"; message: Message}

export interface ConduktAgent {
  run(prompt: string, options?: {signal?: AbortSignal}): AsyncGenerator<AgentEvent, void>
  history(): Message[]
  free(): void
}

export function initialize(moduleOrPath?: RequestInfo | URL | WebAssembly.Module): Promise<void>

export function createAgent(options: {
  inference: Inference
  tools?: Tool[]
  systemPrompt?: string
}): Promise<ConduktAgent>

export function createHttpInference(options?: {
  endpoint?: string
  model?: string
  fetch?: typeof fetch
}): Inference
