defmodule Condukt.SessionStore.Snapshot do
  @moduledoc """
  Serializable session snapshot persisted by session stores.
  """

  alias Condukt.Message

  @type t :: %__MODULE__{
          messages: [Message.t()],
          model: String.t() | nil,
          thinking_level: Condukt.thinking_level() | nil,
          system_prompt: String.t() | nil
        }

  defstruct messages: [],
            model: nil,
            thinking_level: nil,
            system_prompt: nil
end
