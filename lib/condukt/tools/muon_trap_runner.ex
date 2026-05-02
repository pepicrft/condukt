defmodule Condukt.Tools.MuonTrapRunner do
  @moduledoc false

  def cmd(command, args, opts), do: MuonTrap.cmd(command, args, opts)
end
