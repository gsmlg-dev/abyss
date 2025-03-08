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
    {:abyss, "~> 0.1.0"}
  ]
end
```

## Run Example

```shell
# run service
mix run --no-halt -e 'Code.require_file("example/echo.ex"); Abyss.Logger.attach_logger(:trace); Abyss.start_link(handler_module: Echo, port: 1234); Process.sleep(3600_000); '

mix run --no-halt -e 'Abyss.Logger.attach_logger(:trace); Abyss.start_link(handler_module: Abyss.Echo, port: 1234); Process.sleep(300_000); '

# test
while true
do 
  echo "Hello, UDP $(date +%T)" | nc -4 -u -w1 127.0.0.1 1234
done
```
