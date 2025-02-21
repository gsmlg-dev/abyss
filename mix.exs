defmodule Abyss.MixProject do
  use Mix.Project

  @source_url "https://github.com/gsmlg-dev/abyss.git"
  @version "0.0.0"

  def project do
    [
      app: :abyss,
      version: @version,
      elixir: "~> 1.14.1 or ~> 1.15",
      start_permanent: Mix.env() == :prod,
      description: "Abyss is a pure Elixir UDP server",
      aliases: aliases(),
      package: package(),
      deps: deps(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
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
      publish: [
        "format",
        fn _ ->
          File.rm_rf!("priv")
          File.mkdir!("priv")
        end,
        "hex.publish --yes"
      ]
    ]
  end
end
