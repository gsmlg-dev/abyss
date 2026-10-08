# UDP broadcast and multicast

Abyss hosts UDP application callbacks. A datagram, including an empty payload,
remains one message. Successful sends mean local submission, not acknowledged
network delivery. UDP requires no QUIC engine; the optional QUIC integration
retains its separate connection and protocol ownership.

## Start an endpoint

The examples use protocol-neutral payloads and unprivileged ports. Run them only
on a test interface or in the isolated fixture; substitute its actual address,
interface name, and port. No subnet broadcast is guessed.

```elixir
defmodule DatagramEcho do
  use Abyss.Handler

  @impl true
  def handle_data({peer, port, payload}, state) do
    :ok = state.server_config.transport_module.send(state.socket, peer, port, payload)
    {:close, state}
  end
end

{:ok, broadcast_server} = Abyss.start_link(
  handler_module: DatagramEcho,
  port: 49_001,
  broadcast: true,
  transport_module: Abyss.Transport.UDP.Broadcast,
  transport_options: [ip: {0, 0, 0, 0}],
  num_connections: 32
)

{:ok, multicast_server} = Abyss.start_link(
  handler_module: DatagramEcho,
  port: 49_002,
  transport_module: Abyss.Transport.UDP.Multicast,
  transport_options: [
    ip: {0, 0, 0, 0},
    add_membership: {{239, 255, 42, 1}, "test0"},
    add_membership: {{239, 255, 42, 2}, "test0"},
    multicast_if: "test0",
    multicast_loop: true,
    multicast_ttl: 1,
    strict_group_filter: true
  ],
  num_connections: 32
)
```

Broadcast permission, receive activation, membership, and callback lifetime are
separate. Transport defaults are passive. The server owns binary reception and
uses `active: :once` to limit mailbox delivery; user `active: true` or list mode
is rejected by the host. A handler does not own or close the shared socket.
`{:continue, state}` preserves the application state/lifetime; the next packet
from the same peer is not automatically assigned to that handler. Use the
existing dispatcher for opt-in persistent routing. The legacy broadcast mode
remains one-shot and invokes cleanup with the returned application state.

Broadcast/multicast receive endpoints use one socket, independent of
`num_connections`. Automatic socket scaling is incompatible with this mode and
is rejected. `port: 0` reports the actual endpoint through
`Abyss.Listener.listener_info/1`; an ephemeral unicast endpoint also uses one
socket instead of allocating unrelated ports in a pool.

## Memberships and IPv6

```elixir
:ok = Abyss.join(multicast_server, {{239, 255, 42, 3}, "test0"})
Abyss.memberships(multicast_server)
:ok = Abyss.leave(multicast_server, {{239, 255, 42, 3}, "test0"})
```

These service APIs apply to one receiving endpoint and remain responsive without
incoming packets. Memberships are canonicalized before comparison. Duplicate
joins and absent leaves are idempotent; the same group on different interfaces
remains distinct. Desired membership is preserved across a listener restart,
updated only after a successful OS operation, and bounded to 64 entries.
Pausing an existing socket does not rejoin its groups. Startup membership operations are applied individually after opening the socket;
this also avoids OTP treating IPv6 startup memberships as a single scalar. A
failed membership startup closes its temporary socket and existing joins; stopping closes all socket memberships.

IPv4 selectors are local IPv4 addresses, interface names, or `:any` / `{0,0,0,0}`.
An explicitly selected missing interface returns `{:error, :enodev}`; invalid
addresses, family mismatches, and failed joins return explicit errors. Interface
names must be up and have the requested address family where required. Receiving
membership and outgoing `multicast_if` selection are distinct operations. A
sender does not need to join a group.

IPv6 has no broadcast. Use `:inet6`, an IPv6 wildcard binding, and an existing
positive interface index or name:

```elixir
group6 = {0xFF02, 0, 0, 0, 0, 0, 0, 42}
{:ok, server6} = Abyss.start_link(
  handler_module: DatagramEcho,
  port: 49_003,
  transport_module: Abyss.Transport.UDP.Multicast,
  transport_options: [
    :inet6,
    {:ip, {0, 0, 0, 0, 0, 0, 0, 0}},
    {:add_membership, {group6, "test0"}},
    {:multicast_if, "test0"},
    {:multicast_ttl, 1},
    {:multicast_loop, true}
  ]
)
```

The OS resolves the named interface to an index. Link-local client sends select
a scope with `interface: "test0"` or `interface: index, scope_id: index`. A
conflicting/missing scope is rejected; actual route/send failures are returned.
The scoped client send uses OTP's native `inet` sockaddr map API (OTP 24.3
or newer). OTP 27/28 `gen_udp_socket` does not accept scoped sockaddr maps;
with `inet_backend: :socket`, the supported transport send returns
`{:error, {:unsupported_capability, :scoped_sockaddr_send, :socket}}` and the
client rejects the request before opening a socket. Scope is never discarded.
Use `inet_backend: :inet` for the documented IPv6 multicast send path.
IPv6 multicast interface/hop/loop controls are currently supported on Linux,
using its tested IPv6 socket-option ABI on both OTP backends. Other platforms
return `{:error, {:unsupported_capability, :ipv6_multicast_options, platform}}`
rather than applying IPv4 options to IPv6 sockets. The
project's Elixir minimum remains unchanged; minimum-runtime execution still
requires the acceptance matrix, rather than assuming newer runtime evidence
covers every older version. Linux OTP 27 / Elixir 1.18.4 portable and multicast/host subsets were run separately and passed.

## Client queries and bounded collection

```elixir
Abyss.Client.broadcast({255, 255, 255, 255}, 49_001, "limited",
  interface: "test0", source: {192, 0, 2, 1})

# The caller supplies the destination derived from its fixture's netmask.
Abyss.Client.broadcast({192, 0, 2, 255}, 49_001, "directed",
  interface: "test0", source: {192, 0, 2, 1})

# Ephemeral sender; the service replies to the query's source port.
Abyss.Client.multicast_query({239, 255, 42, 1}, 49_002, "query", 500,
  interface: "test0", source: {192, 0, 2, 1},
  reply_mode: :unicast, max_responses: 32, max_response_bytes: 65_536)

# Group replies require a bound group port and membership.
Abyss.Client.multicast_query({239, 255, 42, 1}, 49_002, "query", 500,
  interface: "test0", membership_interface: "test0",
  reply_mode: :multicast, bind_port: 49_002, loopback: true)

Abyss.Client.subscribe_broadcast({239, 255, 42, 1}, 49_002, 500,
  membership_interface: "test0", with_metadata: true,
  on_ready: fn endpoint -> IO.inspect(endpoint, label: "subscription ready") end)

Abyss.Client.broadcast(group6, 49_003, "ipv6", interface: "test0",
  hop_limit: 1, loopback: true)
```

All helpers use the same validated source, family, interface, and bind settings.
Explicit Linux unicast/broadcast interface selection uses `bind_to_device` on
the real socket, with no trial socket or route fallback. If privileges/backend
support are insufficient, its OS error is returned. Other platforms reject
explicit device binding instead of promising an unrelated egress route.
Multicast uses the OS multicast interface option. IPv4 `source` binds outbound
queries; subscription/group-reply reception instead binds wildcard and uses
`membership_interface` independently. `ttl` / `hop_limit` defaults to 1 and
`loopback` defaults to true. Explicit values are respected; no application
protocol-specific TTL is imposed.

Single-response helpers retain `{:ok, binary}` / `{:error, reason}`.
`multicast_query` retains `{:ok, [{peer, port, payload}]}` when no ancillary
fields are present; actual ancillary receive fields extend that tuple to
`{peer, port, ancillary, payload}`. Subscriptions return binaries by default,
or those actual peer tuples with `with_metadata: true`.

Collection uses one absolute finite deadline, defaults to at most 256 retained
responses and 1,048,576 payload bytes, and counts empty payloads as an item.
Bounds are positive integers; negative/infinite collection timeouts are invalid.
Exceeding a bound returns `{:error, {:response_limit, :count | :bytes}, partial}`
and does not retain the overflowing packet. Socket errors return
`{:error, reason, partial}`. Only deadline/receive timeout ends normally with
`{:ok, collected}`. Every temporary socket closes on success, failure, overflow,
or callback exceptions. Sends are checked before waiting for any response.

## Pause, drain, and resource limits

`Abyss.suspend(server)` stops new admission while admitted workers may reply
through the original socket. Datagrams actually received while suspended are
discarded. The bounded kernel queue may retain packets while receive credit is
withheld, including during an outstanding start; some may be received after
resume. Pause is an admission barrier, not a universal kernel flush.
`Abyss.resume(server)` uses the same socket and desired memberships and reports
errors if it cannot rearm reception.

Ordinary UDP uses deterministic drop-new admission with a shared per-server
`num_connections` limit including reserved starts and live handlers. There is
no pending payload retry queue or per-rejection sleeping Task. One outstanding
start per receiver temporarily withholds receive credit; `admission_start_timeout`
bounds that handshake. Datagram buffers are large enough for ordinary maximum
UDP packets before enforcing `max_packet_size`; truncated prefixes are not an
acceptable packet-size check. UDP receive control bounds local work, not network
backpressure. `active: :once` bounds ingress credit to one complete UDP message
per receiver; the receive buffer is 65,536 bytes. A datagram larger than
`max_packet_size` can temporarily occupy its complete receive binary before the
size check rejects it. An outstanding start payload is bounded by
`max_packet_size`. Admission retained-byte measurements cover reservations and
admitted work, not all transient BEAM binaries or kernel queue memory.
OS receive queue drops cannot be counted reliably.

`Abyss.stop(server, deadline_ms)` drains admitted ordinary handlers against one
absolute overall deadline before closing the shared socket, then forces cleanup
when that deadline expires. Persistent dispatcher mode has a narrower host-stop
contract; this task does not redesign application-level QUIC session draining.

Internal housekeeping does not extend handler idle deadlines. Explicit handler
progress resets token-tagged timers, stale timers are ignored, and `:infinity`
is supported without disabling admission limits. Process memory samples are
bytes, not words, and are not a strict total-memory bound: blocking callbacks,
shared binaries, and inter-sample spikes remain relevant.

## OTP multicast option behavior

OTP 28.5 native socket opening collapses multiple IPv6 membership options in
`inet:add_opt/4`; therefore Abyss opens the socket then applies each membership
operation through the public socket-option API, closing the socket if startup
fails. The regression checks actual Linux OS membership entries, not successful
`drop_membership` returns (the inet driver can suppress some OS option errors).

On IPv6 sockets, generic OTP `multicast_ttl` and `multicast_loop` set IPv4 controls.
A generic `multicast_if` index also fails or leaves the IPv6 egress interface
unset. Abyss maps these options to Linux IPv6 interface/hop/loop options
(IPPROTO_IPV6 41, option numbers 17/18/19), including runtime setters/getters.
Tests compare independent raw kernel values on both backends; the isolated
native fixture validates hops and loopback by actual delivery. On the Linux
socket backend, named IPv4 `multicast_if`/`multicast_ttl`/`multicast_loop` controls
also fail independently on OTP 27; Abyss maps them to IPPROTO_IP 0, options
32/33/34 for open/runtime operations and restores public getters. The socket
fixture verifies these controls through actual IPv4 egress, TTL and loopback.
Socket-backend memberships use the Linux raw `ip_mreqn`/`ipv6_mreq` ABI because
OTP's generic setter rejects membership tuples. Non-Linux socket-backend
multicast controls/memberships are explicitly unsupported until tested. See
[`udp-otp-multicast-defects.md`](udp-otp-multicast-defects.md) for exact reproducers.

## Metadata, options, metrics, and platform limits

Scalar options use the first user value, followed by defaults. Family aliases
(`:inet` / `:inet6`) and mode aliases (`:binary` / `:list` / `mode`) share a key;
explicit conflicting user choices fail. Membership operations preserve distinct
group/interface pairs and meaningful add/drop order. Raw four-tuples remain
ordered operations. `inet_backend` stays first as required by OTP.

Received peer and available ancillary fields are preserved. Local wildcard
`sockname` is the binding, not the destination/group/interface of a packet.
Abyss does not infer destination metadata from membership lists. Strict group
isolation requires `strict_group_filter: true` on the supported platform; basic
OS membership defaults can deliver traffic for groups joined by another socket.
On IPv6, wildcard sockets may also receive same-group traffic across interfaces
within a namespace, including local loopback emissions. Incoming membership
interface selection alone does not promise strict per-interface socket filtering.
Use a tested explicit device bind when that stronger restriction is required;
this facade rejects unsupported `strict_group_filter: true` for IPv6.
Payload bytes are never used to deduplicate legitimate packet delivery.

Metrics use the logical server PID and socket registration so two servers with
the same handler remain independent. Supported transport sends report actual
local send outcomes/bytes; handler termination does not imply a response was
sent. Direct `:gen_udp.send` calls bypass this accounting. Legacy handler-module
queries aggregate registered server scopes rather than inventing peer labels.

| Capability | Linux inet backend | Linux socket backend | macOS | Older runtime |
|---|---|---|---|---|
| IPv4 unicast/broadcast/multicast exchange | Fast tests and 14-gate isolated network fixture PASS | Isolated IPv4 wire gates and bounded multicast query PASS | Runnable portable tests; NOT RUN locally | Linux OTP 27 scoped tests PASS; other minimum combinations NOT RUN |
| IPv6 membership/index and explicit scope configuration | OS membership table and prepared wire, interface, hop, loopback gates PASS | Membership/index/hop/loop kernel settings PASS; scoped wire send explicitly unsupported | IPv6 multicast controls explicitly rejected pending a tested option ABI | Named-index support returns explicit error if unavailable |
| Scoped IPv6 client send | OTP sockaddr map API plus actual IPv6 egress index | Explicit unsupported-capability error on OTP 27/28 | IPv6 multicast controls explicitly rejected | Requires OTP 24.3 sockaddr API |
| Strict IPv4 per-socket group isolation | Tested IP_MULTICAST_ALL=0 | Explicitly rejected | Explicitly rejected | Backend/platform restriction retained |
| Strict IPv6 group isolation | Explicitly rejected | Explicitly rejected | Explicitly rejected | Explicitly rejected |
| Explicit broadcast/unicast device egress | Linux bind_to_device; errors preserved | Backend/permissions may reject | Explicitly rejected | Backend/permissions may reject |
| Raw option failure reporting | OTP inet may ignore unsupported raw options | OS/backend dependent | NOT RUN locally | Backend dependent |
| Destination/interface ancillary metadata | Only fields actually returned by OTP | Only fields actually returned by OTP | NOT RUN locally | No fabricated fields |

Linux loopback tests exercise actual library send/receive paths, but they do not
prove two-interface isolation, routed hop limits, or independent Python peers.
Use the isolated network harness and the gate statuses in
[`udp-hardening-acceptance.md`](udp-hardening-acceptance.md) for those claims.
