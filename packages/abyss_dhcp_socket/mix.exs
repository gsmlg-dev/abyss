defmodule AbyssDhcpSocket.MixProject do
  use Mix.Project

  def project do
    [
      app: :abyss_dhcp_socket,
      version: "0.1.0",
      elixir: "~> 1.13",
      description: "Optional interface-bound DHCP and raw ARP sockets for Abyss",
      deps: [{:rustler, "~> 0.34", runtime: false}],
      package: [
        licenses: ["MIT"],
        files: ~w(lib mix.exs README.md LICENSE native/dhcp_socket/src
                  native/dhcp_socket/Cargo.toml native/dhcp_socket/Cargo.lock
                  native/dhcp_socket/.cargo),
        links: %{"GitHub" => "https://github.com/gsmlg-dev/abyss"}
      ]
    ]
  end

  def application, do: [extra_applications: [:logger]]
end
