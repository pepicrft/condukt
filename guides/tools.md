# Tools

Tools are the things an agent can do beyond generating text. Condukt ships
with a small set of file and shell tools, plus a behaviour for adding your
own.

## Built-in tool sets

```elixir
def tools, do: Condukt.Tools.coding_tools()    # Read, Bash, Edit, Write
def tools, do: Condukt.Tools.read_only_tools() # Read, Bash
```

You can mix the helpers with extras:

```elixir
def tools do
  Condukt.Tools.read_only_tools() ++ [MyApp.Tools.Weather]
end
```

## Built-in tools

| Tool | Description |
| ---- | ----------- |
| `Condukt.Tools.Read` | Read file contents. Supports images. |
| `Condukt.Tools.Bash` | Run a shell command via `bash -c`. |
| `Condukt.Tools.Command` | Run one trusted executable without shell parsing. |
| `Condukt.Tools.Edit` | Surgical file edits using find and replace. |
| `Condukt.Tools.Write` | Create or overwrite files. |

## Scoped command grants

`Condukt.Tools.Command` is a safer alternative to `Bash` when you want to
expose a single executable without giving the model a full shell. It also
lets you attach trusted environment variables that the model never sees.

```elixir
defmodule MyApp.ReviewAgent do
  use Condukt

  @impl true
  def tools do
    [
      Condukt.Tools.Read,
      {Condukt.Tools.Command, command: "git"},
      {Condukt.Tools.Command,
       command: "gh",
       env: [GH_TOKEN: System.fetch_env!("GH_TOKEN")]}
    ]
  end
end
```

Each scoped command tool accepts:

* `args` is an array of strings passed directly to the executable
* `cwd` overrides the agent's working directory for this call
* `timeout` caps execution time in seconds

## Defining a custom tool

Implement `Condukt.Tool`:

```elixir
defmodule MyApp.Tools.Weather do
  use Condukt.Tool

  @impl true
  def name, do: "get_weather"

  @impl true
  def description, do: "Gets the current weather for a location"

  @impl true
  def parameters do
    %{
      type: "object",
      properties: %{
        location: %{type: "string", description: "City name"}
      },
      required: ["location"]
    }
  end

  @impl true
  def call(%{"location" => location}, _context) do
    case WeatherAPI.get(location) do
      {:ok, data} -> {:ok, "Temperature: #{data.temp}F"}
      {:error, reason} -> {:error, reason}
    end
  end
end
```

The second argument to `call/2` is a context map that includes:

* `:agent` is the agent PID
* `:cwd` is the working directory
* `:opts` is the keyword list from `{Module, opts}`

## Parameterized tools

Tools can be added more than once with different options. The `name/1`,
`description/1`, and `parameters/1` callbacks receive those options:

```elixir
defmodule MyApp.Tools.Database do
  use Condukt.Tool

  @impl true
  def name(opts), do: "query_#{opts[:table]}"

  @impl true
  def description(opts), do: "Query the #{opts[:table]} table"

  @impl true
  def parameters(_opts) do
    %{type: "object", properties: %{q: %{type: "string"}}, required: ["q"]}
  end

  @impl true
  def call(args, context) do
    table = context.opts[:table]
    {:ok, MyApp.Repo.query!(table, args["q"])}
  end
end

# In the agent:
def tools do
  [
    {MyApp.Tools.Database, table: "users"},
    {MyApp.Tools.Database, table: "orders"}
  ]
end
```

## Returning results

`call/2` should return:

* `{:ok, value}` for success. Strings, maps, and lists are all fine. Non
  binary values are JSON encoded before being sent to the LLM.
* `{:error, reason}` for failures. The error is reported back to the model
  so it can recover.
