Mimic.copy(MuonTrap)
Mimic.copy(ReqLLM)

# Virtual sandbox tests are tagged `:virtual_sandbox` and excluded by
# default. They rely on the bashkit NIF and run reliably locally, but on
# Linux CI runners merely loading the NIF in the same BEAM process as the
# rest of the suite has reproduced intermittent segfaults during ExUnit's
# between-test cleanup. Until that is root-caused, opt in explicitly:
#
#   mix test --include virtual_sandbox
#
# Or run only the Virtual sandbox suite:
#
#   mix test --only virtual_sandbox

ExUnit.start(exclude: [virtual_sandbox: true])
