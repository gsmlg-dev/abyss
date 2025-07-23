# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Abyss is a pure Elixir UDP server library that provides a modern, high-performance foundation for building UDP-based services like DNS servers, DHCP servers, or custom UDP applications. It implements a supervisor-based architecture with connection pooling and pluggable transport modules.

## Key Architecture

- **Core Module**: `Abyss` - Main API entry point
- **Server**: `Abyss.Server` - Supervisor that manages listener pools and connection supervisors
- **Transport**: `Abyss.Transport` - Behaviour for UDP transport layer (currently uses `Abyss.Transport.UDP`)
- **Listener Pool**: `Abyss.ListenerPool` - Manages UDP listener processes
- **Connection Handling**: `Abyss.Connection` - Handles individual UDP connections/clients
- **Handler**: `Abyss.Handler` - Behaviour for implementing custom request/response logic

## Development Commands

### Build & Test
```bash
# Install dependencies
mix deps.get

# Run tests
mix test

# Run tests with coverage
mix test --cover

# Format code
mix format

# Run dialyzer for type checking
mix dialyzer

# Run credo for code quality
mix credo

# Generate documentation
mix docs

# Publish package
mix publish  # Runs format + hex.publish
```

### Running Examples

```bash
# Basic echo server
mix run --no-halt -e 'Abyss.Logger.attach_logger(:trace); Abyss.start_link(handler_module: Abyss.Echo, port: 1234); Process.sleep(:infinity)'

# DNS forwarder
mix run --no-halt -e 'Code.require_file("example/dns_forwarder.ex"); Abyss.Logger.attach_logger(:trace); Abyss.start_link(handler_module: HandleDNS, port: 53); Process.sleep(:infinity)'

# DNS recursive resolver
mix run --no-halt -e 'Code.require_file("example/dns_recursive.ex"); Abyss.Logger.attach_logger(:trace); Abyss.start_link(handler_module: HandleDNS, port: 53); Process.sleep(:infinity)'

# DHCP listener
mix run --no-halt -e 'Code.require_file("example/dump_dhcp.ex"); Abyss.Logger.attach_logger(:trace); Abyss.start_link(handler_module: DumpDHCP, port: 67, broadcast: true, transport_options: [broadcast: true, multicast_if: {255, 255, 255, 255}]); Process.sleep(:infinity)'

# mDNS listener
mix run --no-halt -e 'Code.require_file("example/dump_mdns.ex"); Abyss.Logger.attach_logger(:trace); Abyss.start_link(handler_module: DumpMDNS, port: 5353, broadcast: true, transport_options: [broadcast: true, multicast_if: {224, 0, 0, 251}]); Process.sleep(:infinity)'
```

### Testing with netcat
```bash
# Test echo server
echo "Hello, UDP" | nc -4 -u -w1 127.0.0.1 1234

# Continuous testing
while true; do echo "Hello, UDP $(date +%T)" | nc -4 -u -w1 127.0.0.1 1234; done
```

## Core Components

### Handler Implementation
Create custom handlers by implementing the `Abyss.Handler` behaviour:

```elixir
defmodule MyHandler do
  @behaviour Abyss.Handler

  @impl true
  def handle_packet(data, {ip, port}, socket) do
    # Process incoming UDP packet
    response = process_data(data)
    
    # Send response back to client
    Abyss.Transport.send(socket, response)
    
    {:ok, state}
  end
end
```

### Configuration Options
Key options when starting Abyss:
- `port`: UDP port to listen on
- `handler_module`: Your handler module
- `num_acceptors`: Number of listener processes (default: 100)
- `num_connections`: Max concurrent connections (default: :infinity)
- `broadcast`: Enable broadcast mode for DHCP/mDNS
- `transport_options`: Additional UDP socket options

## Project Structure

```
lib/
├── abyss.ex              # Main API
├── abyss/
│   ├── server.ex         # Supervisor
│   ├── server_config.ex  # Configuration
│   ├── listener_pool.ex  # Listener management
│   ├── connection.ex     # Connection handling
│   ├── handler.ex        # Handler behaviour
│   ├── transport.ex      # Transport behaviour
│   └── transport/
│       └── udp.ex        # UDP transport implementation
example/                  # Usage examples
├── echo.ex              # Basic echo server
├── dns_forwarder.ex     # DNS forwarding
├── dns_recursive.ex     # DNS recursive resolver
├── dump_dhcp.ex         # DHCP packet sniffer
└── dump_mdns.ex         # mDNS packet sniffer
test/                    # Test files
doc/                     # Generated documentation
```

## Dependencies

- **Core**: Elixir ~> 1.13
- **Telemetry**: Metrics and monitoring
- **Optional**: ex_dns, dhcp_ex (for DNS/DHCP examples)
- **Dev**: dialyxir, credo, ex_doc

## Common Development Tasks

1. **Adding new transport**: Implement `Abyss.Transport` behaviour
2. **Creating new handler**: Implement `Abyss.Handler` behaviour
3. **Testing**: Use `mix test` and example scripts
4. **Documentation**: Update README.md and run `mix docs`
5. **Publishing**: Use `mix publish` (formats + publishes)