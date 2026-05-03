defmodule Condukt.Workflows.ResolverTest do
  use ExUnit.Case, async: false

  alias Condukt.Workflows.{Lockfile, Resolver}

  @moduletag :workflows_nif

  test "uses a satisfying lockfile in offline mode" do
    lockfile = %Lockfile{
      packages: %{
        "github.com/acme/a" => %{
          version: "1.2.0",
          sha256: "abc",
          integrity: "sha256-abc",
          dependencies: []
        }
      }
    }

    requirements = [%Resolver.Requirement{url: "github.com/acme/a", version_spec: "^1.0.0"}]
    assert {:ok, ^lockfile} = Resolver.resolve(requirements, offline: true, lockfile: lockfile)
  end

  test "resolves a synthetic index through the NIF" do
    requirements = [%Resolver.Requirement{url: "github.com/acme/a", version_spec: "^1.0.0"}]

    index = %{
      "github.com/acme/a" => %{
        "1.0.0" => %{
          sha256: String.duplicate("a", 64),
          integrity: "sha256-test",
          dependencies: [%Resolver.Requirement{url: "github.com/acme/b", version_spec: "^1.0.0"}]
        }
      },
      "github.com/acme/b" => %{
        "1.1.0" => %{
          sha256: String.duplicate("b", 64),
          integrity: "sha256-test",
          dependencies: []
        }
      }
    }

    assert {:ok, packages} = Resolver.resolve(requirements, index: index)
    assert packages["github.com/acme/a"].version == "1.0.0"
    assert packages["github.com/acme/b"].version == "1.1.0"
  end

  test "reports conflicts from the NIF resolver" do
    requirements = [
      %Resolver.Requirement{url: "github.com/acme/a", version_spec: "^1.0.0"},
      %Resolver.Requirement{url: "github.com/acme/b", version_spec: "^2.0.0"}
    ]

    index = %{
      "github.com/acme/a" => %{
        "1.0.0" => %{
          sha256: "",
          integrity: "",
          dependencies: [%Resolver.Requirement{url: "github.com/acme/b", version_spec: "^1.0.0"}]
        }
      },
      "github.com/acme/b" => %{
        "1.0.0" => %{sha256: "", integrity: "", dependencies: []},
        "2.0.0" => %{sha256: "", integrity: "", dependencies: []}
      }
    }

    assert {:error, {:no_solution, _message}} = Resolver.resolve(requirements, index: index)
  end

  test "parses strict external load requirements" do
    assert {:ok, %Resolver.Requirement{url: "github.com/acme/tools", version_spec: "1.2.3"}} =
             Resolver.parse_requirement("github.com/acme/tools/lib/export.star@v1.2.3")

    assert {:ok,
            %Resolver.Requirement{
              url: "gitlab.com/acme/platform/support-workflows.git",
              version_spec: "1.2.3"
            }} =
             Resolver.parse_requirement("gitlab.com/acme/platform/support-workflows.git/lib/export.star@v1.2.3")

    assert :relative = Resolver.parse_requirement("./helpers.star")
    assert {:error, {:missing_version, _}} = Resolver.parse_requirement("github.com/acme/tools")
    assert {:error, {:missing_load_path, _}} = Resolver.parse_requirement("github.com/acme/tools@v1.2.3")

    assert {:error, {:invalid_requirement, _}} =
             Resolver.parse_requirement("github.com/acme/tools/lib/export.txt@v1.2.3")
  end
end
