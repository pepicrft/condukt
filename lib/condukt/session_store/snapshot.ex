defmodule Condukt.SessionStore.Snapshot do
  @moduledoc """
  Serializable session snapshot persisted by session stores.
  """

  defstruct messages: [],
            model: nil,
            thinking_level: nil,
            system_prompt: nil
end
