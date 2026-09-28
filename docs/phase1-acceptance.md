# Abyss Phase 1 acceptance — G-A

Date: 2026-09-28. **G-A: PASS for the scoped QUIC v1 application-service subset.**
The gate has public application-consumption evidence, real independent-peer
traffic and clean production-consumer release evidence. This is not a QUIC
conformance certification, security audit, DoQ or HTTP/3 acceptance.

This is the implementation acceptance checkpoint, before the separately
authorized integration and publication. HEAD and uncommitted-status statements
below describe that checkpoint. The release follow-up ran `mix test` successfully:
532 tests and 3 doctests, zero failures, 12 excluded; the scoped integration checks
below cover the relevant exclusions. Release version: 0.6.0, using the existing
workflow's package-version substitution rather than changing the source placeholder.

## Source identity and preserved work

| Input | Actual identity |
| --- | --- |
| Requested review baseline | `37cda667a4af0036e5ac1de7817fc8f0f19fff82` |
| Initial and final Abyss HEAD | `21c76accfa1478f84344200ffa72e846ec9e3006` |
| Initial branch → work branch | `main` → `codex/phase1-quic-service` |
| Implementation revision | **Uncommitted working tree**, not a published fix revision |
| ex_quic G-T, fetched Git dependency | `27779b72da0c784787142012fee3e229fe5397df` |
| ex_ssl G-S, fetched engine dependency | `f1327e0bb7fb2093b8dc2b07e72b26233a739963` |
| Adjacent ex_ssl checkout, inspected only | `fb47051355c9d0a29caee046fa060a745ad0ce5b`, not the consumed pin |
| Independent peer | `aioquic==1.2.0`, CPython 3.12.13 via `uv` |
| Runtime | Elixir 1.18.5, OTP 28.5.0.5, ERTS 16.4.0.5, Linux |

Initial worktree changes consisted only of the untracked user plan
`03-abyss-plan.md`. Its SHA-256 remains
`9b520c0248efbb997bb83c68c04d11d9995f4c7742f7fecad1a6bf274d60284f`.
No existing AGENTS.md was found; the supplied instructions were followed.
The requested initial source files, existing tests and upstream public consumer,
I/O and adapter contracts were inspected. Both upstream acceptance reports mark
their scoped prerequisites PASS. No adjacent repository was changed, and no
upstream API or tag was invented. No push, merge, tag or publication occurred.

`phase1-evidence/source-sha256.txt` identifies the delivered implementation/test
files independently of unchanged HEAD. Consumer lockfiles record the fetched
Git pins and transitive packages. Test credentials come from that pinned ex_ssl
fixture; they are not deployment credentials.

## Delivered application contract

`Abyss.QUIC.child_spec/1` and `start_link/1` start a listener configured with a
concrete bind address, port, TLS credentials, opaque ALPN list, one handler and
finite resource/time limits. `local/1` and `stop/2` expose lifecycle operations.
Implement `Abyss.QUIC.Handler.init/3`, `handle_event/2` and optional `terminate/2`.
Initialization receives a ready generation handle and negotiated metadata before
data callbacks. Stream-open precedes data readiness. The facade exposes
`ready`, `info`, `open_stream`, `read`, `send_stream`, `reset_stream`, `stop_stream`,
`close`, `events` and `operation_status` through public engine operations.

The service owns the socket, external I/O host, bounded writer and application
binding. `QUIC.Endpoint` alone owns CIDs and protocol connection state. Consumer
callbacks execute in isolated per-connection workers, with bounded event batches
and explicit read credit; there is no process per packet. TLS negotiates ALPN,
and no payload sniffing or application-protocol routing occurs. FIN is directional.
Transport, TLS and local handler failures retain distinct reasons; valid opaque
application codes pass unchanged. Readiness does not authenticate a client identity.

Writer credit is acquired before payloads enter its mailbox and covers queued
and in-flight work. Admission references, local socket completion timestamps and
unknown outcomes remain distinct. Timeouts never prove cancellation; callers
must resolve retained references and must not blindly retry. Waiters/results have
finite retention and are cleaned on completion, timeout, caller death or teardown.
Listener drain stops ingress before waiting and has a shared deadline. Connection
close cannot close the shared socket. Host component failure closes the listener;
supervision creates a fresh generation, never an old TLS transcript.

See [quic-service.md](quic-service.md) for configuration, callback events,
ownership and application setup, and [dispatcher.md](dispatcher.md) for writer
receipts. The independent `examples/quic_echo` and `examples/quic_collect`
applications have different handlers and custom ALPNs; adding collection required
no core routing change. `examples/udp_echo` has no ex_quic dependency.

## Per-item acceptance

| Item | Status | Evidence |
| --- | --- | --- |
| A-00 supported supervised application service | PASS | Public facade/behaviour, metadata, ready/open ordering, production consumer projects |
| A-00 validation and bounded attachment | PASS | Missing engine, bad handler/ALPN/TLS/options reject startup; engine bounds pre-attachment queues; failed attachment and delayed init regressions |
| A-00 bidi/uni streams, bounded reads/writes, directional FIN | PASS | Both initiators/directions, server single 16 KiB write, peer and server receive after FIN |
| A-00 opaque errors and local callbacks | PASS | Real reset `74565`, stop `344865`, close `1118481`; init/crash/timeout isolation |
| A-01 pre-mailbox item/byte credit | PASS | Deterministic blocked transport and suspended-gate tests; queued/in-flight bytes remain reserved |
| A-01 completion, timeout and generation contract | PASS | Admission versus timestamp/unknown; unknown/expired/stale references; late outcomes and replacement waiter timer regression |
| A-01 bounded waiter/result/monitor retention | PASS | Caller timeout/death, unused reservation cleanup, idle expiry, bounded results and route monitor replacement |
| A-02 bounded shutdown and failure propagation | PASS | Ingress stopped at drain start; owner/endpoint/writer/receiver death; blocked-send teardown; failed callback initialization |
| A-02 restart and connection isolation | PASS | Transient child stop/restart, stale generation/terminal events; real writer death/restart and one closed connection with 1 MiB on its survivor |
| A-02 writer progress while listener suspended | PASS | Real 1 MiB echo transfer while service process is suspended |
| A-03 independent application integration | PASS | Separate echo/collection custom ALPN listeners; simultaneous slow collection plus two echo connections; all three projects copied outside checkout |
| A-03 Retry off/on, loss, invalid/expired tokens | PASS | Pinned peer; dropped first Retry then two Retry observations; corrupted token and 10 ms token TTL rejection |
| A-03 host Retry egress | PASS | Trace of actual socket-send calls in this listener's writer observes Retry and subsequent protected packets |
| A-03 small windows and cumulative transfer | PASS | 16 KiB receive/retention windows; 1 KiB incremental slow consumption; multiple transfers of 1,048,576 bytes |
| A-03 CA/ALPN and consumer failure negatives | PASS | Wrong CA/ALPN rejected before application binding; real failed/crashed/timed-out consumers leave independent echo operational |
| A-04 ordinary UDP without engine | PASS | Independent UDP consumer and production release assert `Code.ensure_loaded?(QUIC) == false`, reject QUIC activation and exchange UDP echo |
| A-04 QUIC dependency activation and clean release | PASS | Outside-checkout production release includes real QUIC/SSL modules, starts normally and exchanges 1 MiB with peer |
| A-04 default lifecycle/transports/Rust NIF | PASS | 231 UDP/config/echo tests + 57 lifecycle tests; native crate built through ordinary consumer compilation |
| Prerequisites and upstream blockers | PASS | Immutable G-T/G-S fetched; Retry capability works; no unresolved upstream blocker |
| Full repository suite, coverage threshold, Dialyzer/Credo | NOT RUN | Scoped tests/strict compilation used; no claim about unrelated suites |
| Other Elixir/OTP versions, platforms, security audit | NOT RUN | Evidence is restricted to the runtime above |
| Publishing/remote CI/deployment | NOT RUN | Not authorized or required for this local gate |

There are no unresolved FAIL or BLOCKED items within A-00–A-04. Expected injected
failures are asserted negatives, not successful application operations.

## Reproducible checks and actual results

Commands below run from the Abyss root unless stated otherwise. Tests use seed
`28092026`. `--no-cover` avoids the repository-wide coverage alias for these
scoped runs; no test was deleted to achieve a pass.

```sh
mix format --check-formatted
mix compile --warnings-as-errors
MIX_ENV=test mix compile --warnings-as-errors
git diff --check
bash -n scripts/phase1/check.sh scripts/phase1/release_check.sh scripts/phase1/independent_check.sh
python -m py_compile scripts/phase1/peer.py
mix hex.build
```

**PASS**: formatting, dev/test strict compilation, patch whitespace, harness syntax
and local package build. The package contains the runtime QUIC service and its
documentation; no ex_quic dependency was added to the Abyss root. Existing optional
development DNS/DHCP dependencies were preserved, not introduced by this change.
Package evidence: [package-build.log](phase1-evidence/package-build.log).

```sh
mix test --no-cover test/abyss/dispatcher_test.exs test/abyss/quic_test.exs --seed 28092026
mix test test/abyss/server_config_test.exs test/abyss/transport/udp_test.exs test/abyss/transport/udp/core_test.exs test/abyss/transport/udp/unicast_test.exs test/abyss/transport/udp/broadcast_test.exs test/integration/echo_test.exs --include integration --no-cover --seed 28092026
mix test --no-cover test/abyss/listener_test.exs test/abyss/listener_comprehensive_test.exs test/abyss/server_test.exs test/shutdown_listener_test.exs test/abyss/connection_test.exs --include integration --seed 28092026
```

**PASS**: respectively 37 tests, 231 tests plus 3 doctests, and 57 tests; zero
failures. Total: **325 tests and 3 doctests**. Host service tests use a fake backend
to control lifecycle barriers and are not counted as network evidence.
Logs: [host](phase1-evidence/host-regressions-final.log),
[UDP](phase1-evidence/udp-regressions.log),
[lifecycle](phase1-evidence/lifecycle-regressions.log).

```sh
scripts/phase1/check.sh
scripts/phase1/release_check.sh
scripts/phase1/independent_check.sh
```

**PASS**, all commands exit 0. `check.sh` runs real credential validation, stream
traffic, fault injection, control/Retry scenarios and lifecycle checks using
`uv run --python 3.12 --with aioquic==1.2.0 python scripts/phase1/peer.py ...`.
The consumer uses fetched Git dependencies rather than adjacent source paths.
The latest [network log](phase1-evidence/network-final.log) records
`NETWORK_BASELINE_PASS`, `NETWORK_FAULTS_PASS`, all four `CONTROL_PASS` markers and
`NETWORK_LIFECYCLE_PASS`; the writer trace observed one Retry among 4,157 sends.
`sys` inspection/suspension is used only for deliberate host fault injection,
not to discover application connections or implement their consumer interface.

`release_check.sh` builds and boots ordinary production releases, runs UDP and
real QUIC verification through release RPC, then stops both. Startup readiness
RPC is retried at most five times; application verification is executed once.
Initial `:noconnection` messages are startup observations, not ignored transfer
failures. [Release log](phase1-evidence/releases-final.log).

`independent_check.sh` copied only project source and lockfiles to
`/tmp/abyss-phase1-consumers.j5UgHf`, fetched dependencies and built both production
releases there from empty build directories. `ABYSS_PATH` selects this candidate.
It also compiled/started the independent collection application and verified its
1 MiB hash after send-side FIN. The log includes `UDP_WITHOUT_QUIC_PASS`,
`QUIC_RELEASE_PASS`, `OUTSIDE_CHECKOUT_COLLECT_PASS` and real peer results.
[Outside-checkout evidence](phase1-evidence/independent-consumers-final.log).

## Failures found before the final pass

Regression and network failures were retained and repaired, not hidden:

- An early concurrent writer reservation implementation crashed on a reservation
  record during network traffic. Admission now atomically marks and forwards a
  submitted reservation, preserving credit across timeout/death; writer regressions
  cover those paths.
- The first echo handler assumed writes always admitted. After retaining definite
  blocked writes, a second real failure exposed an application credit deadlock:
  an atomic 16 KiB pending write exceeded residual peer credit while the peer
  awaited half-window consumption. Increasing the peer timeout did not fix it.
  The example now echoes 1 KiB chunks and retains a separate single 16 KiB test.
  This obeys the engine's documented admission contract; it is not an upstream
  bug or a hidden core workaround. [Diagnostic](phase1-evidence/credit-diagnostic.log).
- Invalid credentials initially returned a live listener. The real startup
  regression failed; public TLS preflight now rejects before starting a process.
  A subsequent startup regression caught asynchronous EXIT delivery after an
  error return; validation now occurs before `GenServer.start_link`.
- Negative engine limits initially passed host validation; the added regression
  failed, then explicit allowed-option/range validation made it pass.
- Drain initially kept the receiver alive while waiting for workers. A regression
  failed before moving ingress shutdown to the beginning of cleanup.
- A stale waiter deadline could affect a replacement waiter. Deadline messages
  now identify the exact waiter monitor; the regression preserves the replacement.
- The first UDP consumer verification expected the wrong cached-address shape,
  and initial release RPC raced boot. The harness now matches the public tuple
  and separates bounded boot checks from single-shot application verification.

Saved red evidence: [TLS](phase1-evidence/config-red.log),
[engine limits](phase1-evidence/engine-config-red.log),
[startup EXIT](phase1-evidence/startup-red.log),
[drain](phase1-evidence/drain-red.log),
[waiter](phase1-evidence/waiter-red.log). Earlier intermediate logs remain locally
under ignored `_build/phase1/checkpoints`; the final logs above are authoritative.
Fault-injection logs intentionally contain consumer crashes/host termination.
An echo worker can also report an ordinary closed/invalid-operation result when
a peer closes during its callback; that error is propagated and isolated, not
converted into successful delivery.

## Remaining capability limits and handoff

The supported engine subset excludes DATAGRAM, resumption/0-RTT, migration,
server mTLS, wildcard/ancillary destination metadata and external client endpoints.
HTTP/3/QPACK, DoQ/DNS and WebTransport are not implemented. DNS/DoQ and HTTP/3/QPACK
belong permanently to their independent application servers, not a later Abyss
phase. This task makes no http_fetch changes or HTTP/3 client-session claim.

Writes are at most 16 KiB per admission; there is no per-write peer ACK receipt.
Finite stream tombstones can exhaust a connection's lifetime stream-record
budget. Arbitrary hostile local messages and unbounded application-owned queues
are outside the credit guarantee. Callback watchdogs run in the listener, so
suspending it delays watchdog enforcement/new binding while existing writer and
consumer work can continue. Forced teardown can skip application cleanup hooks.

All implementation, tests, examples, scripts and reports are uncommitted review
artifacts. Integrate by declaring the pinned engine as a normal runtime dependency,
providing real credentials and an ALPN-specific handler, and supervising the public
listener child spec. Select finite application queues and deployment limits using
the documented contracts before deployment.
