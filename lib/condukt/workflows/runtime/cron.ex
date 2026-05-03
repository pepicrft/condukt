defmodule Condukt.Workflows.Runtime.Cron do
  @moduledoc """
  Cron trigger process for workflow runtimes.
  """

  use GenServer

  alias Condukt.Workflows.Runtime.Worker
  alias Crontab.CronExpression.Parser
  alias Crontab.Scheduler

  @doc false
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    expr = Keyword.fetch!(opts, :expr)
    cron = Parser.parse!(expr, extended?(expr))

    state = %{
      workflow: Keyword.fetch!(opts, :workflow),
      cron: cron,
      input: Keyword.get(opts, :input, %{}),
      clock: Keyword.get(opts, :clock, &NaiveDateTime.utc_now/0),
      run_fun: Keyword.get(opts, :run_fun, &Worker.invoke/2),
      timer_ref: nil
    }

    {:ok, schedule_next(state)}
  end

  @impl true
  def handle_info(:fire, state) do
    %{workflow: workflow, input: input, run_fun: run_fun} = state
    Task.start(fn -> run_fun.(workflow.name, input) end)
    {:noreply, schedule_next(%{state | timer_ref: nil})}
  end

  defp schedule_next(%{cron: cron, clock: clock} = state) do
    now = clock.()
    next_run = Scheduler.get_next_run_date!(cron, now)
    delay = max(0, NaiveDateTime.diff(next_run, now, :millisecond))
    %{state | timer_ref: Process.send_after(self(), :fire, delay)}
  end

  defp extended?(expr) do
    expr
    |> String.split(" ", trim: true)
    |> length()
    |> Kernel.==(6)
  end
end
