# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **New configuration options for enhanced control**:
  - `connection_telemetry_sample_rate` (default: 0.05) - Configure sampling rate for connection telemetry events
  - `handler_memory_check_interval` (default: 10_000ms) - Interval for handler memory monitoring
  - `handler_memory_warning_threshold` (default: 100 MB) - Memory threshold for warnings
  - `handler_memory_hard_limit` (default: 150 MB) - Hard memory limit triggering termination

- **Modular UDP transport architecture**:
  - `Abyss.Transport.UDP.Core` - Core UDP socket operations
  - `Abyss.Transport.UDP.Unicast` - Unicast-specific functionality
  - `Abyss.Transport.UDP.Broadcast` - Broadcast-specific functionality

- **Enhanced telemetry metrics**:
  - Rolling window rate calculations for accepts_per_second and responses_per_second
  - Atomic ETS operations for concurrent metric updates
  - Response time tracking with per-request measurements

### Changed

- **Improved listener scaling algorithm**: Changed `calculate_optimal_listeners/2` to use 1:100 ratio (1 listener per 100 connections) instead of 1:1000, providing better granularity for low to medium loads
- **Adaptive timeout calculation**: Now consistently uses milliseconds throughout, improving accuracy and preventing time unit bugs
- **Telemetry sampling**: Connection telemetry events now respect configurable sampling rate from ServerConfig

### Fixed

- **Critical ETS race condition**: Fixed race condition in telemetry metrics table creation when multiple processes initialize simultaneously using try/catch pattern
- **Time unit inconsistency**: Fixed adaptive timeout calculation that was incorrectly mixing native time units with milliseconds in bounds checking
- **Socket leak**: Fixed resource leak in `Abyss.Transport.UDP.Unicast.send_recv/3` by ensuring socket cleanup in all code paths
- **Telemetry rate calculation**: Improved rolling window rate calculations with proper atomic operations and window expiration handling
- **Configuration validation**: Added comprehensive validation for all new configuration options with clear error messages

### Improved

- **Test coverage**: Increased from ~40% to 62%+ coverage
- **Test cleanup**: Removed 5 skipped/placeholder tests for a cleaner test suite (237 tests, 0 failures, 0 skipped)
- **Code quality**: Addressed all critical and medium priority code quality issues
- **Documentation**: Updated CLAUDE.md with comprehensive development guidelines
- **Memory management**: Configurable memory monitoring with graceful degradation

### Technical Details

#### Telemetry Improvements

The telemetry system now uses atomic ETS operations to prevent race conditions:

```elixir
# Before: Non-atomic read-modify-write
count = :ets.lookup_element(table, :accepts_in_window, 2)
:ets.insert(table, {:accepts_in_window, count + 1})

# After: Atomic increment
:ets.update_counter(table, :accepts_in_window, {2, 1})
```

#### Adaptive Timeout Fix

Fixed time unit handling in adaptive timeout calculations:

```elixir
# Before: Mixing native and millisecond units
avg_time_native = Enum.sum(times) / length(times)
timeout = round(avg_time_native * 3)
timeout |> max(div(base_timeout, 2)) |> min(base_timeout * 2)

# After: Consistent millisecond units
avg_time_native = Enum.sum(times) / length(times)
avg_time_ms = System.convert_time_unit(round(avg_time_native), :native, :millisecond)
timeout_ms = round(avg_time_ms * 3)
timeout_ms |> max(div(base_timeout, 2)) |> min(base_timeout * 2)
```

#### Listener Scaling Enhancement

Improved scaling granularity for better performance under varying loads:

```elixir
# Before: 1 listener per 1000 connections
base_listeners = max(div(current_connections, 1000), 1)

# After: 1 listener per 100 connections
base_listeners = max(div(current_connections, 100), 1)
```

## [0.4.0] - Previous Release

Initial stable release with core UDP server functionality, telemetry support, and security features.
