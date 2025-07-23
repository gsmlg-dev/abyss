# Abyss

[![release](https://github.com/gsmlg-dev/abyss/actions/workflows/release.yml/badge.svg)](https://github.com/gsmlg-dev/abyss/actions/workflows/release.yml) 
[![Hex.pm](https://img.shields.io/hexpm/v/abyss.svg)](https://hex.pm/packages/abyss) 
[![Documentation](https://img.shields.io/badge/documentation-gray)](https://hexdocs.pm/abyss)

---

## Installation

The package can be installed by adding `abyss` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:abyss, "~> 0.4.0"}
  ]
end
```

## Run Example

```shell
# run service
mix run --no-halt -e 'Code.require_file("example/echo.ex"); Abyss.Logger.attach_logger(:trace); Abyss.start_link(handler_module: Echo, port: 1234); Process.sleep(:infinity); '

mix run --no-halt -e 'Abyss.Logger.attach_logger(:trace); Abyss.start_link(handler_module: Abyss.Echo, port: 1234); Process.sleep(:infinity); '

# test
while true
do 
  echo "Hello, UDP $(date +%T)" | nc -4 -u -w1 127.0.0.1 1234
done
```

## Run DNS Server Example

```shell
# run forwarder
mix run --no-halt -e 'Code.require_file("example/dns_forwarder.ex"); Abyss.Logger.attach_logger(:trace); Abyss.start_link(handler_module: HandleDNS, port: 53); Process.sleep(:infinity); '

mix run --no-halt -e 'Code.require_file("example/dns_forwarder.ex"); Abyss.start_link(handler_module: Abyss.HandleDNS, port: 53); Process.sleep(:infinity); '
```

```shell
# run forwarder
mix run --no-halt -e 'Code.require_file("example/dns_recursive.ex"); Abyss.Logger.attach_logger(:trace); Abyss.start_link(handler_module: HandleDNS, port: 53); Process.sleep(:infinity); '

mix run --no-halt -e 'Code.require_file("example/dns_recursive.ex"); Abyss.start_link(handler_module: Abyss.HandleDNS, port: 53); Process.sleep(:infinity); '
```

Listen `broadcast`

DHCP

```shell
mix run --no-halt -e 'Code.require_file("example/dump_dhcp.ex"); Abyss.Logger.attach_logger(:trace); Abyss.start_link(handler_module: DumpDHCP, port: 67, broadcast: true, transport_options: [broadcast: true, multicast_if: {255, 255, 255, 255}]); Process.sleep(:infinity); '
# or
mix run --no-halt -e 'Code.require_file("example/dump_dhcp.ex"); Abyss.start_link(handler_module: DumpDHCP, port: 67, broadcast: true, transport_options: [broadcast: true, multicast_if: {255, 255, 255, 255}]); Process.sleep(:infinity); '
```

mDNS

```shell
mix run --no-halt -e 'Code.require_file("example/dump_mdns.ex"); Abyss.Logger.attach_logger(:trace); Abyss.start_link(handler_module: DumpMDNS, port: 5353, broadcast: true, transport_options: [broadcast: true, multicast_if: {224, 0, 0, 251}]); Process.sleep(:infinity); '
# or
mix run --no-halt -e 'Code.require_file("example/dump_mdns.ex"); Abyss.start_link(handler_module: DumpMDNS, port: 5353, broadcast: true, transport_options: [broadcast: true, multicast_if: {224, 0, 0, 251}]); Process.sleep(:infinity); '
```
