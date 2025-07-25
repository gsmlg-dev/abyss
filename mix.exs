defmodule Abyss.MixProject do
  use Mix.Project

  @source_url "https://github.com/gsmlg-dev/abyss"
  @version "0.0.0"

  def project do
    [
      app: :abyss,
      version: @version,
      elixir: "~> 1.13",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      name: "Abyss",
      description: "Abyss is a pure Elixir UDP server",
      source_url: @source_url,
      dialyzer: dialyzer(),
      aliases: aliases(),
      package: package(),
      deps:
        deps(
          File.exists?(Path.expand("../ex_dns", __DIR__)) and
            File.exists?(Path.expand("../ex_dhcp", __DIR__)) and is_nil(System.get_env("CI"))
        ),
      docs: docs(),
      test_coverage: [
        ignore_modules: [
          ~r[Abyss.Test.*]
        ],
        summary: [threshold: 40]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps(true) do
    [
      {:telemetry, "~> 1.0"},
      {:telemetry_metrics, "~> 1.0"},
      {:ex_dns, path: "../ex_dns", only: [:dev, :test], runtime: false, optional: true},
      {:dhcp_ex, path: "../ex_dhcp", only: [:dev, :test], runtime: false, optional: true},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false},
      {:machete, ">= 0.0.0", only: [:dev, :test]},
      {:ex_doc, ">= 0.0.0", runtime: false}
    ]
  end

  defp deps(false) do
    [
      {:telemetry, "~> 1.0"},
      {:telemetry_metrics, "~> 1.0"},
      {:ex_dns, "~> 0.3", only: [:dev, :test], runtime: false, optional: true},
      {:dhcp_ex, "~> 0.3", only: [:dev, :test], runtime: false, optional: true},
      {:machete, ">= 0.0.0", only: [:dev, :test]},
      {:ex_doc, ">= 0.0.0", runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false}
    ]
  end

  defp dialyzer do
    [
      plt_core_path: "priv/plts",
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_deps: :apps_direct,
      plt_add_apps: [:public_key],
      flags: [
        "-Werror_handling",
        "-Wextra_return",
        "-Wmissing_return",
        "-Wunknown",
        "-Wunmatched_returns",
        "-Wunderspecs"
      ]
    ]
  end

  defp package do
    [
      maintainers: ["Jonathan Gao"],
      licenses: ["MIT"],
      files: ~w(lib LICENSE mix.exs README.md),
      links: %{
        Github: @source_url,
        Changelog: "https://hexdocs.pm/abyss/changelog.html"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_url: @source_url,
      source_ref: "v#{@version}"
    ]
  end

  defp aliases do
    [
      test: ["test --cover"],
      "test.all": ["test --include integration --include slow"],
      "test.unit": ["test --exclude integration --exclude slow"],
      "test.integration": ["test --include integration"],
      ci: [
        "format --check-formatted",
        "credo --strict",
        "test --cover --include integration"
      ],
      publish: [
        "format",
        "hex.publish --yes"
      ]
    ]
  end
end
