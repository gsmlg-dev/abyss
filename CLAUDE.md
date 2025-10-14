# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Abyss is a pure Elixir UDP server library that provides a modern, high-performance foundation for building UDP-based services like DNS servers, DHCP servers, or custom UDP applications. It implements a supervisor-based architecture with connection pooling and pluggable transport modules.

## Key Architecture

- **Core Module**: `Abyss` - Main API entry point
- **Server**: `Abyss.Server` - Supervisor that manages listener pools and connection supervisors
- **Server Config**: `Abyss.ServerConfig` - Configuration management and validation
- **Transport**: `Abyss.Transport` - Behaviour for UDP transport layer (currently uses `Abyss.Transport.UDP`)
- **Listener Pool**: `Abyss.ListenerPool` - Manages UDP listener processes with supervisor strategies
- **Connection Handling**: `Abyss.Connection` - Handles individual UDP connections/clients via DynamicSupervisor
- **Handler**: `Abyss.Handler` - Behaviour for implementing custom request/response logic
- **Telemetry**: `Abyss.Telemetry` - Metrics and monitoring via :telemetry
- **Logger**: `Abyss.Logger` - Structured logging with different levels

## Development Commands

### Build & Test
```bash
# Install dependencies
mix deps.get

# Run tests (includes coverage by default)
mix test

# Run specific test types
mix test.unit              # Unit tests only
mix test.integration       # Integration tests only
mix test.all              # All tests including slow ones

# Run tests with coverage explicitly
mix test --cover

# Format code
mix format

# Run dialyzer for type checking
mix dialyzer

# Run credo for code quality
mix credo

# Run credo with strict checks (used in CI)
mix credo --strict

# Generate documentation
mix docs

# Publish package
mix publish  # Runs format + hex.publish

# Full CI pipeline check
mix ci  # Runs format check, credo strict, and integration tests
```

### Running Examples

```bash
# Basic echo server (using Echo module from example/echo.ex)
mix run --no-halt -e 'Code.require_file("example/echo.ex"); Abyss.Logger.attach_logger(:trace); Abyss.start_link(handler_module: Echo, port: 1234); Process.sleep(:infinity)'

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
  use Abyss.Handler

  @impl true
  def handle_data({ip, port, data}, state) do
    # Process incoming UDP packet
    response = process_data(data)

    # Send response back to client
    Abyss.Transport.UDP.send(state.socket, ip, port, response)

    {:continue, state}  # Continue handling more packets
    # or
    {:close, state}     # Close connection after response
  end
end
```

### Configuration Options
Key options when starting Abyss:
- `port`: UDP port to listen on
- `handler_module`: Your handler module (required)
- `num_listeners`: Number of listener processes (default: 100)
- `num_connections`: Max concurrent connections (default: 16_384)
- `broadcast`: Enable broadcast mode for DHCP/mDNS (default: false)
- `transport_options`: Additional UDP socket options
- `read_timeout`: Connection read timeout (default: 60_000ms)
- `shutdown_timeout`: Graceful shutdown timeout (default: 15_000ms)

## Project Structure

```
lib/
├── abyss.ex              # Main API entry point
├── abyss/
│   ├── server.ex         # Main supervisor managing all components
│   ├── server_config.ex  # Configuration validation and defaults
│   ├── listener_pool.ex  # Pool of listener processes (supervisor)
│   ├── listener.ex       # Individual listener process
│   ├── connection.ex     # Connection lifecycle management
│   ├── handler.ex        # Handler behaviour and GenServer implementation
│   ├── transport.ex      # Transport behaviour definition
│   ├── transport/
│   │   └── udp.ex        # UDP transport implementation
│   ├── telemetry.ex      # Telemetry event handling
│   ├── logger.ex         # Structured logging utilities
│   └── shutdown_listener.ex # Graceful shutdown coordination
example/                  # Usage examples and demos
├── echo.ex              # Basic echo server
├── dns_forwarder.ex     # DNS forwarding to upstream servers
├── dns_recursive.ex     # DNS recursive resolver
├── dump_dhcp.ex         # DHCP packet monitoring
├── dump_mdns.ex         # mDNS packet monitoring
└── dump.ex              # Generic packet dumping
test/
├── abyss/               # Unit tests for core modules
├── integration/         # Integration tests
└── support/             # Test utilities and helpers
doc/                     # Generated documentation
```

## Dependencies

- **Core**: Elixir ~> 1.13
- **Runtime**:
  - `telemetry` - Metrics and monitoring
  - `telemetry_metrics` - Telemetry metric aggregation
- **Optional Dev Dependencies**:
  - `ex_dns` - DNS protocol handling (for examples)
  - `dhcp_ex` - DHCP protocol handling (for examples)
- **Development Tools**:
  - `dialyxir` - Static type analysis via Dialyzer
  - `credo` - Code quality and style analysis
  - `ex_doc` - Documentation generation
  - `machete` - Test utilities and assertions

## Testing Strategy

### Test Organization
- **Unit tests**: Test individual modules in `test/abyss/`
- **Integration tests**: Test end-to-end functionality in `test/integration/`
- **Test support**: Common test utilities in `test/support/`

### Test Execution
```bash
# Run all tests with coverage (default behavior)
mix test

# Run only fast unit tests
mix test.unit

# Run integration tests (may require network access)
mix test.integration

# Run all tests including slow ones
mix test.all

# Run specific test file
mix test test/abyss/server_test.exs

# Run tests matching a pattern
mix test --only unit
```

### Test Coverage
- Target coverage threshold: 40% (configured in mix.exs)
- Coverage reports generated automatically with `mix test`
- Test modules excluded from coverage: `Abyss.Test.*`

## Common Development Tasks

### 1. Adding New Transport Modules
Implement the `Abyss.Transport` behaviour:
```elixir
defmodule Abyss.Transport.MyTransport do
  @behaviour Abyss.Transport

  @impl true
  def listen(port, options) do
    # Implementation for listening on given port
  end

  # Implement all required callbacks...
end
```

### 2. Creating Custom Handlers
Use the `Abyss.Handler` behaviour:
```elixir
defmodule MyHandler do
  use Abyss.Handler

  @impl true
  def handle_data({ip, port, data}, state) do
    # Your custom logic here
    {:continue, state}
  end

  # Optional callbacks for error handling, timeouts, etc.
end
```

### 3. Running Examples for Development
```bash
# Start with trace logging for debugging
mix run --no-halt -e 'Abyss.Logger.attach_logger(:debug); Code.require_file("example/echo.ex"); Abyss.start_link(handler_module: Echo, port: 1234); Process.sleep(:infinity)'
```

### 4. Development Workflow
```bash
# 1. Make changes
# 2. Run formatter
mix format

# 3. Run type checker
mix dialyzer

# 4. Run code quality checks
mix credo --strict

# 5. Run tests
mix test

# 6. Full CI check
mix ci
```

### 5. Documentation Updates
- Update module docs with `@moduledoc`
- Run `mix docs` to generate HTML documentation
- Update README.md for user-facing changes

### 6. Publishing Releases
```bash
# Ensure all checks pass
mix ci

# Bump version in mix.exs if needed
# Update CHANGELOG.md

# Publish to Hex
mix publish
```

## Architecture Deep Dive

### Supervisor Tree
```
Abyss (main supervisor)
├── Abyss.ListenerPool (supervisor)
│   ├── Abyss.Listener (listener process 1)
│   ├── Abyss.Listener (listener process 2)
│   └── ... (up to num_listeners processes)
├── DynamicSupervisor (connection supervisor)
│   ├── Handler process 1 (per UDP packet)
│   ├── Handler process 2 (per UDP packet)
│   └── ... (up to num_connections processes)
├── Task (activator - starts listeners)
└── Abyss.ShutdownListener (coordinates graceful shutdown)
```

### Request Flow
1. **Listener Pool**: Manages multiple listener processes for load distribution
2. **Listener**: Waits for UDP packets on the bound port
3. **Connection**: Creates handler processes for incoming packets
4. **Handler**: Processes packet data using user-defined logic
5. **Transport**: Handles low-level UDP socket operations

### Broadcast Mode
When `broadcast: true` is set:
- Only one listener process is created (regardless of `num_listeners`)
- Packets are processed in broadcast mode (useful for DHCP/mDNS)
- Handler processes terminate after processing each packet

### Telemetry Events
Abyss emits comprehensive telemetry events for monitoring:
- `[:abyss, :listener, :start/stop/ready/waiting]`
- `[:abyss, :connection, :start/stop/ready/send/recv]`
- `[:abyss, :acceptor, :start/stop/spawn_error]`

Use `Abyss.Logger.attach_logger(:level)` to enable logging at different levels.

## Debugging and Development Tips

### Common Issues
1. **Port already in use**: Ensure port is not bound by another process
2. **Permission denied**: Avoid privileged ports (< 1024) or run with sudo
3. **Handler crashes**: Check that handler modules implement required callbacks
4. **Connection limits**: Adjust `num_connections` if hitting max connections

### Debugging Commands
```bash
# Start with debug logging
mix run --no-halt -e 'Abyss.Logger.attach_logger(:debug); # your server code'

# Check listener pool status
# In IEx: Abyss.ListenerPool.listener_pids(pid)

# Check connection supervisor status
# In IEx: Abyss.Server.connection_sup_pid(pid)
```

### Performance Tuning
- **num_listeners**: Increase for high-throughput scenarios (default: 100)
- **num_connections**: Set appropriate limits for your use case
- **read_timeout**: Adjust based on expected protocol timing
- **transport_options**: Tune UDP buffer sizes as needed

## Key Patterns

### Handler State Management
```elixir
defmodule MyHandler do
  use Abyss.Handler

  @impl true
  def handle_data({ip, port, data}, state) do
    # Access socket via state.socket
    # Store custom state in state map
    new_state = Map.put(state, :last_client, {ip, port})
    {:continue, new_state}
  end
end
```

### Error Handling
```elixir
@impl true
def handle_error(reason, state) do
  Logger.error("Handler error: #{inspect(reason)}")
  # Cleanup resources
end
```

### Timeout Handling
```elixir
@impl true
def handle_data({ip, port, data}, state) do
  # Set custom timeout for next packet
  {:continue, state, 30_000}  # 30 second timeout
end

@impl true
def handle_timeout(state) do
  Logger.warn("Connection timed out")
  # Timeout cleanup logic
end
```