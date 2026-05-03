# condukt_workflows

Rustler NIF for the `Condukt.Workflows` subsystem.

The crate evaluates Starlark workflow declarations, resolves shared workflow
packages, and hashes content-addressed package trees. It is distributed through
the same precompiled NIF release flow as `condukt_bashkit`.

## Entry points

* `eval/3`: evaluate a Starlark workflow file on a dirty CPU scheduler.
* `parse_only/2`: parse a Starlark workflow file without evaluating it.
* `resolve/3`: solve package versions with PubGrub on a dirty CPU scheduler.
* `sha256_tree/1`: hash a package tree on a dirty I/O scheduler.
