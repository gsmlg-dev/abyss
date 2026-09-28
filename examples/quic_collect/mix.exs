defmodule AbyssCollectExample.MixProject do
  use Mix.Project

  def project do
    [
      app: :abyss_quic_collect_example,
      version: "0.1.0",
      elixir: "~> 1.18",
      deps: [
        {:abyss, path: System.get_env("ABYSS_PATH", "../..")},
        {:ex_quic,
         git: "https://github.com/gsmlg-dev/ex_quic.git",
         ref: "27779b72da0c784787142012fee3e229fe5397df"}
      ]
    ]
  end

  def application,
    do: [extra_applications: [:logger, :public_key], mod: {AbyssCollectExample.Application, []}]
end
