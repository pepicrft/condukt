%{
  configs: [
    %{
      name: "default",
      requires: [
        "./credo/checks/no_nested_modules.ex"
      ],
      checks: %{
        extra: [
          {Condukt.Credo.Check.Readability.NoNestedModules, []}
        ]
      }
    }
  ]
}
