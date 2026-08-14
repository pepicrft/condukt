%{
  configs: [
    %{
      name: "default",
      requires: [
        "./credo/checks/no_nested_modules.ex",
        "./credo/checks/no_typespecs.ex",
        "./credo/checks/no_rescue.ex"
      ],
      checks: %{
        extra: [
          # Credo's default `files.included` lists "web/", so the nested
          # `condukt_site` Phoenix app is analysed by this config too. These
          # two are house rules for the library's own source, not for a
          # generated Phoenix app that documents its public functions with
          # typespecs, so they stop at the library boundary. NoRescue is a
          # correctness rule from AGENTS.md and applies everywhere.
          {Condukt.Credo.Check.Readability.NoNestedModules, files: %{excluded: ["web/"]}},
          {Condukt.Credo.Check.Readability.NoTypespecs, files: %{excluded: ["web/"]}},
          {Condukt.Credo.Check.Readability.NoRescue, []}
        ]
      }
    }
  ]
}
