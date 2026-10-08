# Isolated UDP wire acceptance

Run from the repository root after `mix deps.get && mix compile`:

```sh
python3 scripts/udp/network_fixture.py
ABYSS_UDP_BACKEND=socket python3 scripts/udp/network_fixture.py
```

The harness requires Linux, `ip`, `setpriv`, Python 3, the locked Mix dependencies,
and passwordless `sudo` for creating/deleting network namespaces and their
interfaces. Exit 77 means fixture setup was blocked and is **not acceptance**;
the CI job treats it as a failing gate. Missing packets and socket errors fail
with exit 1. A final `{"result": "PASS", ...}` with exit 0 accepts the native `inet` full
IPv4/IPv6 matrix. The socket run accepts its IPv4 gates with
`{"result": "PASS_SUPPORTED_SUBSET", ...}` and explicitly lists scoped IPv6 wire
send as unsupported. It also asserts the returned capability error; no IPv6
wire timeout is converted to success. CI runs both backends.

All resources use a unique `abyss-udp-<id>` namespace prefix. Three endpoint
namespaces (Abyss plus two Python standard-library peers) attach to two bridges
inside a fourth, fixture-owned namespace. The networks use 192.0.2.0/24,
198.51.100.0/24, and two private IPv6 prefixes; no interface, route, firewall,
or packet is added to the ambient developer network. All traffic uses high
unprivileged ports, 239.192.74.1/2 and ff02::114/115, low send rates, and unique
epoch payloads. Fixture setup/teardown uses privilege; BEAM and peer workers drop
to the invoking uid/gid before execution. A `finally` block stops workers and
removes every created namespace on normal failure or completion. On an external
SIGKILL, delete only the reported fixture prefix manually.

The service is a real supervised Abyss endpoint with a one-shot handler. Control
acknowledgments prove socket/group readiness before sending. Tests exercise:

- Incoming and outgoing limited/directed IPv4 broadcast; two independent
  receivers and unicast replies from the original listener port.
- IPv4 and scoped IPv6 multicast in both directions; two groups, two
  subscribers, leave/rejoin and duplicate join idempotency.
- The same group on two distinct incoming interfaces; explicit egress selection
  and no delivery on the other isolated network.
- TTL/hop limits measured on received IP ancillary data, and loopback enabled
  versus disabled with a subscriber in the sending namespace plus remote peers.
- Empty payloads and distinct datagram boundaries.

The Python sockets turn Linux `IP_MULTICAST_ALL` / `IPV6_MULTICAST_ALL` off so
independent same-port subscriptions remain group-specific; each peer also binds
explicitly to the selected device for two-interface isolation. The Abyss
endpoint uses one socket for its desired groups. This harness does not claim
cross-platform reuse semantics, router multicast forwarding, source-specific
multicast, reliable UDP under overload, or strict destination metadata on
backends that do not report it. Unit/host tests cover invalid configuration,
startup rollback, truncation/size limits, ancillary tuple normalization, and
resource/lifecycle behavior separately.
