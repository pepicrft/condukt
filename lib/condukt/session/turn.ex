defmodule Condukt.Session.Turn do
  @moduledoc """
  State belonging to the turn a session is currently running.

  These five fields move together and mean nothing apart: whether a turn is in
  flight, the reference that identifies it for aborting, the messages queued to
  join or follow it, and who is watching it. Grouping them keeps the session's
  own struct inside the 32-key limit that decides whether the virtual machine
  stores it as a flat map or a hash map, and, more usefully, makes it obvious
  which parts of a session are per-turn and which outlive one.

  `abort_ref` is the mechanism worth knowing about: the streaming loop carries
  the reference it started with and stops as soon as the session's own no longer
  matches, so aborting is a matter of replacing it rather than reaching into a
  running task.
  """

  defstruct streaming: false,
            abort_ref: nil,
            steering_messages: [],
            follow_up_messages: [],
            subscribers: []

  @doc "A turn that has not started."
  def new, do: %__MODULE__{}

  @doc """
  Marks a turn as started under a fresh abort reference.
  """
  def start(%__MODULE__{} = turn), do: %{turn | streaming: true, abort_ref: make_ref()}

  @doc """
  Marks the turn finished, leaving the queues and subscribers alone.

  Those outlive a single turn: a subscriber stays attached for the next one, and
  a message queued while this turn ran is meant for the one after it.
  """
  def finish(%__MODULE__{} = turn), do: %{turn | streaming: false}

  @doc """
  Abandons the running turn.

  Replacing the reference is what stops the loop: it compares against the
  session's on every iteration and gives up when they differ.
  """
  def abort(%__MODULE__{} = turn), do: %{turn | abort_ref: make_ref(), streaming: false}

  @doc "Adds a subscriber and the monitor watching it."
  def subscribe(%__MODULE__{} = turn, pid, ref, monitor) do
    %{turn | subscribers: [{pid, ref, monitor} | turn.subscribers]}
  end

  @doc """
  Removes one subscription, returning the monitors to demonitor with it.
  """
  def unsubscribe(%__MODULE__{} = turn, pid, ref) do
    {dropped, kept} = Enum.split_with(turn.subscribers, fn {p, r, _m} -> p == pid and r == ref end)
    {%{turn | subscribers: kept}, Enum.map(dropped, fn {_p, _r, monitor} -> monitor end)}
  end

  @doc "Drops the subscriber a monitor was watching, after it went down."
  def drop_monitored(%__MODULE__{} = turn, monitor) do
    %{turn | subscribers: Enum.reject(turn.subscribers, &match?({_, _, ^monitor}, &1))}
  end

  @doc "The subscribers listening under one reference."
  def listeners(%__MODULE__{} = turn, ref) do
    for {pid, ^ref, _monitor} <- turn.subscribers, do: pid
  end

  @doc "Queues a message to join the running turn."
  def steer(%__MODULE__{} = turn, message) do
    %{turn | steering_messages: turn.steering_messages ++ [message]}
  end

  @doc "Queues a message for after the running turn."
  def follow_up(%__MODULE__{} = turn, message) do
    %{turn | follow_up_messages: turn.follow_up_messages ++ [message]}
  end
end
