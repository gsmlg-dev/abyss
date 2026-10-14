# Operations and development

This guide covers inspecting a running service, understanding its counters, controlling its lifecycle, and checking changes in the repository. Examples using `endpoint` assume a service started with `datagram_handler`.

## Inspect an endpoint

```elixir
{:ok, {address, port}} = Abyss.Endpoint.local_endpoint(endpoint)
{:ok, capabilities} = Abyss.Endpoint.capabilities(endpoint)
{:ok, info} = Abyss.Endpoint.info(endpoint)
metrics = Abyss.Telemetry.get_metrics(endpoint)
```

`info` includes logical identity, socket generation, local endpoint, capabilities and mode. A datagram runtime also exposes input count, retained input bytes, key/timer counts, high-water values, receipts and egress admission state. These describe current host-managed work; they are not an application-memory budget or a kernel drop counter.

The endpoint facade requires one receive owner. Legacy fixed-port unicast pools can have several; inspect individual listeners with `Abyss.Listener.listener_info_cached/1` for cached local addresses rather than assuming a single endpoint.

## Metrics and events

Counters are scoped by the logical server PID. `Abyss.Telemetry.get_metrics()` aggregates all scopes; `get_metrics(handler_module)` aggregates services registered to that legacy handler module. Socket generations share the logical scope, and logical service deletion removes its rows. `reset_metrics/0` resets node-wide counters, so use it deliberately when monitoring multiple services.

| Counter | Meaning |
| --- | --- |
| `datagrams_received`, `bytes_received` | Inputs observed by Abyss reception |
| `datagrams_dropped`, `bytes_dropped` | Explicit library drops; runtime accounting can include serialized event metadata |
| `accepts_total`, `connections_total`, `connections_active` | Validated admission and active work accounting |
| `responses_total`, `bytes_sent` | Successful instrumented local socket sends |
| `send_errors_total` | Instrumented local send failures |
| `work_completed`, `work_failed` | Accounted work outcomes |
| `accepts_per_second`, `responses_per_second` | Rates over the current counter window |

Handler exit alone does not count as a response. Raw `:gen_udp` or `:socket` sends bypass Abyss transport instrumentation. A send counter or receipt does not establish peer delivery.

```elixir
:telemetry.attach_many(
  "abyss-datagrams",
  [[:abyss, :datagram, :dropped], [:abyss, :datagram, :send]],
  fn event, measurements, metadata, _config ->
    IO.inspect({event, measurements, metadata})
  end,
  nil
)

# Detach when the observer is no longer needed.
:telemetry.detach("abyss-datagrams")
```

Drop metadata contains `server_id` and `reason`; send metadata contains `server_id` and `result`. Measurements include `bytes`. Listener and legacy connection spans are documented in `Abyss.Telemetry`. Connection spans are sampled by `connection_telemetry_sample_rate` (default 0.05); admission/send counters are not controlled by that sampling setting. Avoid unbounded peer or route-key labels in external metric storage.

`Abyss.Logger.attach_logger(:info)` attaches the built-in structured logger. Choose the level and event collection appropriate for the service.

## Pause, resume and stop

```elixir
:ok = Abyss.Endpoint.pause(endpoint)
:ok = Abyss.Endpoint.resume(endpoint)
:ok = Abyss.Endpoint.stop(endpoint, 5_000)
```

Pause retains the socket, port and desired memberships and lets admitted work reply. Newly received packets are dropped while paused; packets left in the kernel queue may arrive after resume. Resume reuses the existing generation unless the owner restarted.

Stop shares an absolute deadline across admitted work and forced cleanup. A finite timeout limits draining, not successful remote delivery. Cleanup may leave previously admitted send outcomes unknown. Legacy services use `Abyss.suspend/1`, `resume/1` and `stop/2`. QUIC uses its own application drain API; generic dispatcher host cleanup is not a completed QUIC session drain.

Tune `max_packet_size`, `num_connections`, datagram `runtime_options`, and writer item/byte limits together. Empty payloads still consume an item. The library's quotas do not bound arbitrary application state, hostile local mailbox messages or kernel queues. Refer to the [migration defaults](udp-runtime/migration.md) and [writer contract](dispatcher.md) before changing limits.

## Scoped verification

From the repository root, use the installed Elixir/Mix environment, or prefix commands with `devenv shell --` when using the project devenv. Fetch dependencies before the first build.

```sh
mix deps.get
mix docs --warnings-as-errors
mix format --check-formatted mix.exs

# Datagram contracts and runtime lifecycle
mix test --no-cover test/abyss/datagram_test.exs test/abyss/datagram_config_test.exs test/abyss/endpoint_contract_test.exs test/abyss/datagram_runtime_test.exs

# Legacy host, admission and memberships
mix test --no-cover test/abyss/udp_host_hardening_test.exs test/abyss/udp_admission_test.exs test/abyss/udp_membership_host_test.exs

# Dispatcher and QUIC host contracts
mix test --no-cover test/abyss/dispatcher_test.exs test/abyss/quic_test.exs
```

Choose checks for the changed area. `--no-cover` avoids the whole-project coverage threshold for a focused run. Unit and host tests do not replace independent network fixtures. Elixir 1.18 with OTP 27/28 on Linux and OTP 28 on macOS are covered by the regression workflow; the declared Elixir `~> 1.13` minimum has not been validated by that matrix.

The [UDP fixture instructions](https://github.com/gsmlg-dev/abyss/blob/main/scripts/udp/README.md) describe isolated broadcast/multicast/native traffic and optional DHCP consumers. They require Linux namespace tooling and fixture privileges; setup failure or exit 77 is not acceptance. The [QUIC scripts](https://github.com/gsmlg-dev/abyss/tree/main/scripts/phase1) check independent peers and consumers separately.

For performance comparisons, run the same workload serially on source-identified baseline and candidate checkouts without competing builds. Historical [0.8 measurements](https://github.com/gsmlg-dev/abyss/blob/main/docs/archive/udp-runtime/performance.md) include a legacy throughput regression and materially slower new-policy results for a tiny sequential workload; no universal speedup is claimed.
