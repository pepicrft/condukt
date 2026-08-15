defmodule Condukt.CLI.MixProject do
  use Mix.Project

  # The terminal agent ships on the library's release train, so the version is
  # read from the root project rather than duplicated here. `scripts/version.exs
  # set` only rewrites the root `mix.exs`; reading it keeps both in lockstep
  # without teaching the release script about a second file.
  @external_resource "../mix.exs"
  @version (case Regex.run(~r/@version "(\d+\.\d+\.\d+)"/, File.read!("../mix.exs"), capture: :all_but_first) do
              [version] -> version
              _ -> raise "unable to read @version from ../mix.exs"
            end)

  def project do
    [
      app: :condukt_cli,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      test_ignore_filters: [~r/test\/support\//]
    ]
  end

  def application do
    [
      mod: {Condukt.CLI.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # The agent loop, tools, sandbox, and provider plumbing all come from the
      # library. This project is only the terminal layer on top of it.
      {:condukt, path: "..", override: true},

      # Terminal rendering. Ships precompiled NIFs, including the musl variants
      # burrito's linux wrapper needs.
      {:ex_ratatui, "~> 0.13"},

      # Single-file, self-extracting binaries for every supported platform.
      {:burrito, "~> 1.6"},

      # OpenRouter credential validation and the OAuth key exchange. Already in
      # the tree through req_llm; declared so the calls here are not relying on
      # a transitive dependency.
      {:req, "~> 0.5"},
      {:quokka, "~> 2.12", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  # The release is named after the binary, not the OTP application, so burrito
  # emits `condukt_<target>` rather than `condukt_cli_<target>`.
  #
  # Every target is built on a host with the same operating system and CPU:
  # the renderer's NIF is a precompiled artifact resolved from the build host's
  # triple, so a cross-host release would bundle a library the wrapper cannot
  # load. Linux additionally needs `TARGET_ABI=musl`, because burrito's linux
  # wrapper runs a musl runtime; `ExRatatui.Burrito.verify_linux_nif/1` fails the
  # build rather than shipping a glibc library that would break on every machine.
  #
  # There is no Windows target: ex_ratatui publishes no Windows artifact, so the
  # terminal renderer has nothing to load there.
  defp releases do
    [
      condukt: [
        applications: [condukt_cli: :permanent],
        steps: [:assemble, &ExRatatui.Burrito.verify_linux_nif/1, &Burrito.wrap/1],
        burrito: [
          targets: [
            linux: [os: :linux, cpu: :x86_64],
            linux_arm: [os: :linux, cpu: :aarch64],
            macos: [os: :darwin, cpu: :x86_64],
            macos_silicon: [os: :darwin, cpu: :aarch64]
          ]
        ]
      ]
    ]
  end
end
