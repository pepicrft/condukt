Mimic.copy(MuonTrap)
Mimic.copy(ReqLLM)

Code.require_file("support/llm_provider.ex", __DIR__)

# Virtual sandbox tests are tagged `:virtual_sandbox` and excluded by
# default. They rely on the bashkit NIF and run reliably locally, but on
# Linux CI runners merely loading the NIF in the same BEAM process as the
# rest of the suite has reproduced intermittent segfaults during BEAM
# teardown. Until that is root-caused, opt in explicitly:
#
#   mix test --include virtual_sandbox
#
# Or run only the Virtual sandbox suite:
#
#   mix test --only virtual_sandbox

# Workflow NIF tests are similarly opt-in. The broad CI suite compiles
# this module as stubs and leaves native coverage to dedicated checks,
# because loading the workflows NIF on Linux runners can currently segfault
# BEAM during process teardown after tests have already passed:
#
#   mix test --include workflows_nif

ExUnit.start(exclude: [virtual_sandbox: true, workflows_nif: true])
