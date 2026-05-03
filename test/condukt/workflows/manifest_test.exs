defmodule Condukt.Workflows.ManifestTest do
  use ExUnit.Case, async: true

  alias Condukt.Workflows.Manifest

  test "parses a valid manifest" do
    document = %{
      "name" => "demo-workflows",
      "version" => "1.2.3",
      "exports" => ["lib/tools.star"],
      "requires_native" => ["starlark"],
      "signatures" => %{}
    }

    assert {:ok, %Manifest{} = manifest} = Manifest.parse(document)
    assert manifest.name == "demo-workflows"
    assert manifest.version == Version.parse!("1.2.3")
    assert manifest.exports == ["lib/tools.star"]
    assert manifest.warnings == []
  end

  test "rejects invalid names and versions" do
    assert {:error, {:invalid_manifest, _}} =
             Manifest.parse(%{"name" => "Demo", "version" => "1.0.0", "exports" => []})

    assert {:error, {:invalid_manifest, _}} =
             Manifest.parse(%{"name" => "demo", "version" => "not-semver", "exports" => []})
  end

  test "rejects non-star exports" do
    assert {:error, {:invalid_manifest, "exports must be .star paths"}} =
             Manifest.parse(%{"name" => "demo", "version" => "1.0.0", "exports" => ["README.md"]})
  end

  test "warns for unknown native requirements" do
    assert {:ok, manifest} =
             Manifest.parse(%{
               "name" => "demo",
               "version" => "1.0.0",
               "exports" => [],
               "requires_native" => ["custom-nif"]
             })

    assert manifest.warnings == [{:unknown_native_requirement, "custom-nif"}]
  end
end
