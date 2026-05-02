defmodule Condukt.Tools.MuonTrapRunner do
  @moduledoc false

  def cmd(command, args, opts) do
    {:ok, MuonTrap.cmd(command, args, opts)}
  catch
    :error, error -> {:error, format_error(error)}
  end

  defp format_error(error) do
    if is_exception(error) do
      Exception.message(error)
    else
      inspect(error)
    end
  end
end
