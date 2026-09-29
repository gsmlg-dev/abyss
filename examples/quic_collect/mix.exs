defmodule AbyssCollectExample.MixProject do
  use Mix.Project

  def project do
    [
      app: :abyss_quic_collect_example,
      version: "0.1.0",
      elixir: "~> 1.18",
      deps: [
        {:abyss, path: System.get_env("ABYSS_PATH", "../..")},
        {:elixir_quic, "== 0.2.2"}
      ]
    ]
  end

  def application,
    do: [extra_applications: [:logger, :public_key], mod: {AbyssCollectExample.Application, []}]
end
