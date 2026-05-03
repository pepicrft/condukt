defmodule Condukt do
  @moduledoc """
  A framework for building AI agents in Elixir.

  Condukt treats AI agents as first-class OTP processes that can
  reason, use tools, and orchestrate complex workflows.

  ## Defining an Agent

      defmodule MyApp.ResearchAgent do
        use Condukt

        @impl true
        def tools do
          [
            Condukt.Tools.Read,
            Condukt.Tools.Bash
          ]
        end
      end

  ## Running an Agent

      {:ok, agent} = MyApp.ResearchAgent.start_link(
        api_key: "sk-...",
        system_prompt: \"\"\"
        You are a research assistant that helps users find information.
        Be thorough and cite your sources.
        \"\"\"
      )

      {:ok, response} = Condukt.run(agent, "What's new in Elixir 1.18?")

  ## Streaming Responses

      Condukt.stream(agent, "Explain OTP")
      |> Stream.each(fn
        {:text, chunk} -> IO.write(chunk)
        {:tool_call, name, _id, _args} -> IO.puts("\\nCalling: \#{name}")
        {:tool_result, _id, result} -> IO.puts("Result: \#{inspect(result)}")
        :done -> IO.puts("\\nDone!")
      end)
      |> Stream.run()

  ## Core Concepts

  - **Session** - A GenServer managing conversation state and the agent loop
  - **Message** - User, assistant, or tool result messages in the conversation
  - **Tool** - A capability the agent can invoke (read files, run commands, etc.)
  - **Provider** - An LLM backend (Anthropic, OpenAI, Ollama, etc.)
  - **Event** - Notifications during agent execution for streaming/UI
  """

  # ============================================================================
  # Behaviour Definition
  # ============================================================================

  @doc """
  Returns the default system prompt for this agent.

  This can be overridden at `start_link/1` via the `:system_prompt` option.
  If neither is provided, the agent will have no system prompt.
  """
  @callback system_prompt() :: String.t() | nil

  @doc """
  Returns the list of tools this agent can use.
  """
  @callback tools() :: [module() | {module(), keyword()} | struct()]

  @doc """
  Returns the model identifier.

  Uses ReqLLM format: "provider:model", e.g., "anthropic:claude-sonnet-4-20250514"
  """
  @callback model() :: String.t()

  @doc """
  Returns the default thinking level.
  """
  @callback thinking_level() :: :off | :minimal | :low | :medium | :high

  @doc """
  Returns the default sandbox spec for this agent.

  Accepts a module, `{module, opts}`, an already-built `Condukt.Sandbox` struct,
  or `nil` (the session will default to `Condukt.Sandbox.Local`). Can be
  overridden at `start_link/1` via the `:sandbox` option.
  """
  @callback sandbox() :: nil | module() | {module(), keyword()} | Condukt.Sandbox.t()

  @doc """
  Initializes agent state from options.
  """
  @callback init(keyword()) :: {:ok, term()} | {:stop, term()}

  @doc """
  Handles events during execution.
  """
  @callback handle_event(term(), term()) :: {:noreply, term()} | {:stop, term(), term()}

  @optional_callbacks [
    system_prompt: 0,
    tools: 0,
    model: 0,
    thinking_level: 0,
    sandbox: 0,
    init: 1,
    handle_event: 2
  ]

  # ============================================================================
  # __using__ Macro
  # ============================================================================

  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour Condukt

      import Condukt.Operation, only: [operation: 2]

      Module.register_attribute(__MODULE__, :condukt_operations, accumulate: true)
      @before_compile Condukt.Operation

      # Default implementations
      @impl Condukt
      def system_prompt, do: nil

      @impl Condukt
      def tools, do: []

      @impl Condukt
      def model, do: "anthropic:claude-sonnet-4-20250514"

      @impl Condukt
      def thinking_level, do: :medium

      @impl Condukt
      def sandbox, do: nil

      @impl Condukt
      def init(opts), do: {:ok, opts}

      @impl Condukt
      def handle_event(_event, state), do: {:noreply, state}

      defoverridable system_prompt: 0,
                     tools: 0,
                     model: 0,
                     thinking_level: 0,
                     sandbox: 0,
                     init: 1,
                     handle_event: 2

      @doc """
      Starts the agent process.

      ## Options

      - `:api_key` - API key for the LLM provider
      - `:model` - Override the default model (format: "provider:model")
      - `:base_url` - Override the provider's default base URL
      - `:system_prompt` - System prompt for the agent
      - `:load_project_instructions` - Auto-load `AGENTS.md`, `CLAUDE.md`, and local skills from the project root (default: `true`)
      - `:thinking_level` - Override the thinking level
      - `:cwd` - Project working directory used for AGENTS.md/CLAUDE.md
        discovery and disk session storage (default: File.cwd!()). Note: tools
        no longer key off this value directly — they use the active sandbox.
      - `:sandbox` - Sandbox spec for tool I/O (module, `{module, opts}`, or
        `Condukt.Sandbox` struct). Defaults to
        `{Condukt.Sandbox.Local, cwd: <:cwd>}`.
      - `:session_store` - Session store module or `{module, opts}` tuple
      - `:compactor` - Compactor module or `{module, opts}` tuple
        (see `Condukt.Compactor`)
      - `:name` - GenServer registration name

      Plus all standard GenServer options.
      """
      def start_link(opts \\ []) do
        Condukt.Session.start_link(__MODULE__, opts)
      end

      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [opts]},
          type: :worker,
          restart: :permanent
        }
      end
    end
  end

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Runs a prompt and returns the final response.

  Two call shapes are supported:

  ## Against a running agent

  Pass an agent pid (or registered name) and a prompt. Forwards to the
  underlying `Condukt.Session.run/3`.

      {:ok, response} = Condukt.run(agent, "Hello!")
      {:ok, response} = Condukt.run(agent, "Hello!", timeout: 60_000)

  Per-run options:

  - `:timeout` - Max time in ms (default: 300_000)
  - `:max_turns` - Max tool use cycles (default: 50)
  - `:images` - List of images to include

  ## Anonymous run (no agent module)

  Pass a prompt as the first argument. A transient session is built from the
  options, the prompt is run, and the session is torn down. This is the
  scripting entry point: a single function call defines model, system prompt,
  tools, and (optionally) typed input/output.

      {:ok, text} =
        Condukt.run("Summarize the README.",
          model: "anthropic:claude-haiku-4-5",
          tools: [Condukt.Tools.Read]
        )

      # Inline tools
      ls =
        Condukt.tool(
          name: "ls",
          description: "List a directory.",
          parameters: %{
            type: "object",
            properties: %{path: %{type: "string"}},
            required: ["path"]
          },
          call: fn %{"path" => p}, ctx -> Condukt.Sandbox.glob(ctx.sandbox, p <> "/*") end
        )

      {:ok, text} = Condukt.run("List lib/", tools: [ls])

  ### Structured I/O

  Pass `:output` (a JSON Schema map) to switch into structured mode. The
  runtime appends a synthetic `submit_result` tool whose schema matches the
  output schema, runs the loop until the model calls it, validates the
  submitted value with [JSV](https://hex.pm/packages/jsv), and returns
  `{:ok, validated_map}`. Top-level keys are atomized when the schema's
  property keys are atoms.

      {:ok, %{verdict: "approve", summary: _}} =
        Condukt.run("Decide a verdict for this PR and summarize it.",
          input: %{repo: "tuist/condukt", pr_number: 42},
          input_schema: %{
            type: "object",
            properties: %{
              repo: %{type: "string"},
              pr_number: %{type: "integer"}
            },
            required: ["repo", "pr_number"]
          },
          output: %{
            type: "object",
            properties: %{
              verdict: %{type: "string", enum: ["approve", "request_changes", "comment"]},
              summary: %{type: "string"}
            },
            required: ["verdict", "summary"]
          },
          tools: [Condukt.Tools.Read]
        )

  When `:input` is present, the prompt is treated as instructions and
  attached to the system prompt; the args are encoded as the user message.
  When `:input` is absent, the prompt is the user message as-is.

  Failure reasons:

  - `{:invalid_input, %JSV.ValidationError{}}` - args did not match `:input_schema`
  - `{:invalid_output, %JSV.ValidationError{}}` - submitted value failed validation
  - `:no_result_submitted` - structured mode finished without a `submit_result` call

  Anonymous runs accept all the per-run options above (`:timeout`,
  `:max_turns`, `:images`) plus the session options accepted by an agent's
  `start_link/1` (`:model`, `:system_prompt`, `:api_key`, `:base_url`,
  `:thinking_level`, `:tools`, `:sandbox`, `:cwd`, `:session_store`,
  `:compactor`, `:redactor`, `:load_project_instructions`).
  `:load_project_instructions` defaults to `false` for anonymous runs.
  """
  def run(prompt) when is_binary(prompt) do
    Condukt.AnonymousRun.run(prompt, [])
  end

  def run(prompt, opts) when is_binary(prompt) and is_list(opts) do
    Condukt.AnonymousRun.run(prompt, opts)
  end

  def run(agent, prompt) when (is_pid(agent) or is_atom(agent)) and is_binary(prompt) do
    Condukt.Session.run(agent, prompt, [])
  end

  def run(agent, prompt, opts) when (is_pid(agent) or is_atom(agent)) and is_binary(prompt) and is_list(opts) do
    Condukt.Session.run(agent, prompt, opts)
  end

  @doc """
  Builds an inline tool spec usable in any place a tool module is accepted.

  Returns a struct that `Condukt.Session` recognizes alongside module-based
  tools, so an inline tool can be added to an agent's `tools/0` callback or
  passed in `Condukt.run/2`'s `:tools` option.

  ## Required keys

  - `:name` - tool name as the LLM will see it
  - `:description` - human-readable description
  - `:parameters` - JSON Schema map describing the arguments
  - `:call` - 2-arity function `(args, context)` returning `{:ok, result}` or `{:error, reason}`

  The `context` map passed to `:call` matches the context received by
  `Condukt.Tool` callbacks: `:agent`, `:sandbox`, `:cwd`, `:opts` (always
  `[]` for inline tools).

  ## Example

      weather =
        Condukt.tool(
          name: "get_weather",
          description: "Returns the current temperature for a city.",
          parameters: %{
            type: "object",
            properties: %{city: %{type: "string"}},
            required: ["city"]
          },
          call: fn %{"city" => city}, _ctx ->
            {:ok, "72F in \#{city}"}
          end
        )

      {:ok, _} = Condukt.run("What's the weather in Berlin?", tools: [weather])
  """
  def tool(opts) when is_list(opts) do
    %Condukt.Tool.Inline{
      name: Keyword.fetch!(opts, :name),
      description: Keyword.fetch!(opts, :description),
      parameters: Keyword.fetch!(opts, :parameters),
      call: Keyword.fetch!(opts, :call)
    }
  end

  @doc """
  Streams a prompt, yielding events as they occur.

  ## Events

  - `{:text, chunk}` - Text chunk from LLM
  - `{:thinking, chunk}` - Thinking/reasoning chunk
  - `{:tool_call, name, id, args}` - Tool being called
  - `{:tool_result, id, result}` - Tool result
  - `{:error, reason}` - Error occurred
  - `:agent_start` - Agent started processing
  - `:agent_end` - Agent finished
  - `:turn_start` - New LLM turn starting
  - `:turn_end` - Turn completed
  - `:done` - Stream complete
  """
  defdelegate stream(agent, prompt, opts \\ []), to: Condukt.Session

  @doc """
  Returns the conversation history.
  """
  defdelegate history(agent), to: Condukt.Session

  @doc """
  Clears conversation history.
  """
  defdelegate clear(agent), to: Condukt.Session

  @doc """
  Aborts current operation.
  """
  defdelegate abort(agent), to: Condukt.Session

  @doc """
  Runs the configured compactor against the conversation history.

  See `Condukt.Compactor` for details and built-in strategies.
  """
  defdelegate compact(agent), to: Condukt.Session

  @doc """
  Injects a message mid-execution (steering).

  This message will be delivered after the current tool completes,
  and remaining tool calls will be skipped.
  """
  defdelegate steer(agent, message), to: Condukt.Session

  @doc """
  Queues a follow-up message.

  This message will be delivered when the agent finishes its current work.
  """
  defdelegate follow_up(agent, message), to: Condukt.Session
end
