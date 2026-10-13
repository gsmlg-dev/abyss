# Migrating to the UDP datagram API

The unreleased Abyss 0.8 candidate on `codex/udp-runtime` adds an opt-in API. Publication is blocked by [upstream QUIC issue #108](https://github.com/gsmlg-dev/http_fetch/issues/108). Existing `Abyss.start_link(handler_module: Module, ...)`, custom `start_link/1` handlers, transport calls, memberships, dispatcher capabilities and optional QUIC services keep their contracts. Legacy `{:continue, state}` keeps the invocation process alive; it does not route later packets from that peer back to it. Legacy broadcast processing remains one-shot.

## A new consumer

```elixir
defmodule Echo do
  @behaviour Abyss.DatagramHandler
  def init(_options, _context), do: {:ok, 0}
  def handle_datagram(datagram, count) do
    {:ok, count + 1, [{:reply, datagram.payload}]}
  end
end

{:ok, endpoint} = Abyss.Endpoint.start_link(
  datagram_handler: Echo,
  execution: :endpoint,
  port: 0,
  transport_options: [ip: {127, 0, 0, 1}]
)
{:ok, {address, port}} = Abyss.Endpoint.local_endpoint(endpoint)
```

Use `:per_datagram` for one init/transition/cleanup per admitted input, `:endpoint` for one serialized application state, or `:keyed` with an explicitly supplied `route_key: fn datagram -> application_key end`. Route functions receive immutable datagrams and run under a separate watchdog. A key is application-owned; the runtime neither parses protocols nor creates implicit peer sessions. Same-key work is locally serialized; different keys can progress concurrently. This does not imply wire ordering or delivery.

The new API uses exactly one receiver. Multiple/dynamic new receivers are rejected. Handler, new datagram handler and dispatcher selection must be unambiguous. Native sockets require the datagram API. No dummy legacy handler is needed for a dispatcher.

## Bounds and effects

`num_connections` remains the service-wide input item ceiling. `runtime_options` has finite positive integer overrides:

| Option | Default |
|---|---:|
| `max_queue`, `max_keys`, `max_timers` | 128 |
| `max_queue_bytes`, `max_action_bytes` | 1,048,576 |
| `max_key_queue` | 32 |
| `max_key_queue_bytes` | 262,144 |
| `max_key_bytes` | 1,024 |
| `max_actions` | 32 |
| `init_timeout`, `callback_timeout`, `route_timeout` | 1,000 ms |
| `terminate_timeout`, `send_timeout` | 100 ms |
| `idle_timeout` | 60,000 ms |

Input quotas cover queued, initializing, routing and executing work including serialized datagram/event metadata. Persistent keys have separate count/idle bounds. Timer token/value serialized size is at most 4,096 bytes; delay is an unsigned 32-bit millisecond value. Application state itself and arbitrary local mailbox messages are application responsibilities; these quotas are not a whole-VM memory guarantee.

Callbacks return `{:ok, state, actions}`, `{:stop, reason, state, actions}` or `{:error, reason, state}`. Actions are finite lists of `{:reply, binary}`, `{:reply, binary, :strict}`, `{:send, sockaddr, binary}`, `{:timer, token, delay_ms, value}` and `{:cancel_timer, token}`. Timers require a persistent policy. Validate all actions before effects; after submission, multiple effects are not a transaction. Persistent `handle_event/2` receives timer events and generation/token-tagged send outcomes. Outcome events do not recursively generate outcome events.

`Endpoint.send/4` returns `{:ok, ref}` for admission. `Endpoint.await/3` reports local completion, definite error or unknown outcome. Timeout does not cancel accepted work and must not cause blind retries. Endpoint outcome retention is 256 entries/5 seconds; expiry does not establish that a packet was unsent. Writer item/byte bounds include queued and in-flight sends and structured addressing controls.

Pause stops admission while accepted work can still reply. It does not flush the kernel queue. Stop shares one absolute deadline across ingress, callbacks, egress and forced cleanup. Old socket generations invalidate capabilities, timers and receipts; restart may change an ephemeral port. Desired memberships restore through the existing owner, and logical service deletion removes them.

## Backend and capability matrix

`io_backend: :gen_udp` (default) and its `inet_backend: :inet | :socket` driver are different from `io_backend: :socket_native` (direct OTP `:socket`). Explicit driver, boot-time node default and OTP default use one effective resolver; already-opened sockets retain their actual identity.

| Linux OTP 27/28 capability | GenUDP inet | GenUDP socket | Direct native |
|---|---|---|---|
| Ordinary complete/empty IPv4 UDP | Yes | Yes | Yes |
| IPv6 ordinary UDP | Yes | Yes | Yes |
| IPv4 broadcast/multicast | Yes | Yes | Yes |
| IPv6 scoped multicast | Verified | Unavailable | Verified |
| Destination/ingress interface metadata | Unknown | Unknown | Verified IPv4/IPv6 |
| TTL/traffic metadata | When enabled and supported | Runtime dependent | Enabled by default |
| Strict original-source/interface reply | Unavailable | Unavailable | Verified IPv4/IPv6 |
| Strict IPv4 group filter | Linux explicit option | Unavailable | Explicit option |
| Strict interface receive filter | Unavailable | Unavailable | Unimplemented |
| Legacy raw socket handlers/dispatcher | Yes | Yes | Rejected |

Native payload buffer is 65,535 bytes and control buffer is 4,096 bytes. Payload truncation drops the packet. Control truncation leaves unsafe metadata `nil`; strict reply fails, and selected required metadata prevents admission. Tiny receive sub-binaries are copied to avoid retaining larger parent buffers. IPv4 packet destination, usable local source and interface are distinct. IPv6 group local source is selected from the observed ingress interface, preserving scope.

`Endpoint.capabilities/1` reports adapter, driver, family, platform/runtime and each capability's `supported`, `enabled` and unavailable `reason`. `required_capabilities: [:destination, :source_control]` rejects startup unless enabled. `required_metadata: [:destination, :interface_index, :local_address]` drops any individual datagram missing these fields with a measurable reason. Membership alone never proves interface isolation. A route reply uses the peer; strict reply uses the original socket with per-message source/interface controls and fails without metadata. Group replies require an explicit destination.

Native Linux control encodings are checked against system headers and independent peers. Other platforms and OTP versions below 27 reject native startup. Portable GenUDP macOS coverage is handled by CI; the declared Elixir `~> 1.13` requirement remains unchanged but the actual minimum runtime is unverified. Current tested runtime claims are Elixir 1.18 / OTP 27 and 28; no older native support is claimed.

Unicast request/response helpers now reject a wrong resolved address/port under one absolute response deadline. DNS/socket setup remain outside that response budget. Broadcast/multicast helpers keep multi-responder behavior. Directed broadcast cannot be safely inferred without subnet context; select an explicit response policy for ambiguous one-to-many use.

## Dispatcher eligibility

| Configuration | Legacy dispatcher | New API |
|---|---|---|
| UDP/Unicast, `broadcast: false` | Supported | Supported |
| Multicast memberships, `broadcast: false` | Preserved/tested | Supported |
| Broadcast transport or `broadcast: true` | Rejected as before | Supported |
| Native direct socket | Rejected | Supported |

Legacy dispatcher callback-owned input queues are not bounded by the new handler runtime. Its writer/admission/outcome contracts remain independent. QUIC uses the existing service and engine-owned CID/protocol state; UDP execution does not redesign QUIC application draining.

## DHCP dependency migration

Ordinary core installation no longer compiles Rust or loads a native artifact. `Abyss.DhcpSocket.Native` is a pure-Elixir facade. Without the optional package its functions return `{:error, {:missing_optional_dependency, :abyss_dhcp_socket}}`.

DHCP users must explicitly add `packages/abyss_dhcp_socket`; this is a dependency migration, not a zero-change upgrade. The independently buildable package is intentionally unpublished. For a repository dependency on this candidate branch (Mix supporting sparse Git dependencies):

```elixir
{:abyss_dhcp_socket,
 git: "https://github.com/gsmlg-dev/abyss.git",
 branch: "codex/udp-runtime",
 sparse: "packages/abyss_dhcp_socket"}
```

Local opt-in fixtures can instead use an explicit path to the extracted package. Core production metadata declares neither dependency nor local path. The implementation module is `AbyssDhcpSocket.Native`, its OTP app/artifact is `:abyss_dhcp_socket`, and the facade preserves five operations and owner messages. `open/2` returns the resource directly. The package still needs Cargo/Rust and Linux raw ARP/bind capabilities. See [package guidance](../../packages/abyss_dhcp_socket/README.md) and [acceptance evidence](acceptance.md).
