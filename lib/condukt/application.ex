defmodule Condukt.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    register_providers()

    children = []
    Supervisor.start_link(children, strategy: :one_for_one, name: Condukt.Supervisor)
  end

  defp register_providers do
    ReqLLM.Providers.register(Condukt.Providers.Ollama)
  end
end
