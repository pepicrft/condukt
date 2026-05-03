Mimic.copy(MuonTrap)
Mimic.copy(ReqLLM)

# The Virtual sandbox depends on a precompiled (or source-built) NIF. When
# the NIF is unavailable on this platform, exclude the tagged tests rather
# than failing the suite — consumers in environments without the NIF should
# still be able to use Sandbox.Local exclusively.
exclude =
  try do
    _ = Condukt.Bashkit.NIF.module_info(:exports)
    []
  rescue
    _ -> [virtual_sandbox: true]
  catch
    _, _ -> [virtual_sandbox: true]
  end

ExUnit.start(exclude: exclude)
