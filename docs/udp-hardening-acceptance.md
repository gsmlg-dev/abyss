# UDP hardening acceptance

This report covers the repository-local implementation requested by
`abyss-udp-broadcast-multicast-codex-prompt.md`. It is local acceptance, not a
release, remote CI result or general production-readiness declaration.

## Source and environment

- Baseline and final Git HEAD: `671d0d7f004c56e4b170402f074547eed2731d04`, branch `main`.
- Final implementation is **uncommitted**. The supplied prompt was the only
  initial untracked file. No commit, push, merge, tag or publication occurred.
- `udp-evidence/source-manifest.sha256` identifies the final source, tests,
  fixtures, workflows and package configuration independently of HEAD. Run
  `sha256sum --check docs/udp-evidence/source-manifest.sha256` from the root.
  Reports/logs are excluded to avoid a circular fingerprint. Manifest SHA-256: `e81d4cea15c51bba80427c66435e7e38bf386289c1e048d8b3c07adf4d4c3512` (131 files).
- Reference host: NixOS 26.05, x86_64, Linux `6.18.48`, eight BEAM schedulers.
  Main runtime: Elixir `1.18.5`, OTP `28.5.0.5`, ERTS `16.4.0.5`.
- Additional runtime from the existing devenv: Elixir `1.18.4`, OTP
  `27.3.4.6`, ERTS `15.2.7.4`; isolated build path
  `/tmp/abyss-handler-hardening-build`.
- Root and example lockfiles are unchanged. QUIC consumer locks select Hex
  `elixir_quic 0.17.0` and `ex_ssl 0.17.0`, independently checked in the consumer
  logs. Older phase-one reports were preserved and were not relabeled.
  The QUIC package inner/outer checksums are
  `ca0b194046c9b8bc0f1b97704108b696808fa149cce0d583687659b9220576d0` /
  `09bdf0ddc54da37fc5264151110c547fc5d28188b1d34961d98081d95f6d81ba`;
  TLS checksums are
  `a152cc1c9f31b437789de865535e8b244eccacc06d8de5f895d553d160806849` /
  `253b90f7304f09402869d814cf75bd76eb2fbf34bfaf4284822c407312fae095`.
- The DHCP Rust NIF source and lockfile are unchanged and compiled with the
  service. Its existing tests remain in the regression suite. No sibling
  repository, runtime requirement or host LAN configuration was modified.

## Findings and final behavior

The reproduction qualifications for every U1–U5, B1, M1, M2, C1 and T1 finding
are in `udp-hardening-plan.md`. Some were demonstrated by original red tests;
others were source-confirmed and had new invariant coverage. A baseline test
that failed earlier in setup is not counted as reproducing its later assertion.
The two original red summary files explicitly identify transcript extracts;
subsequent raw logs are retained separately.

- **U1/U5:** monotonic tagged idle timers survive bookkeeping, stale/early events
  cannot lose expiry, infinity is deliberate, and memory samples use bytes.
- **U2/U4:** a serialized server-wide ledger counts active and reserved work;
  drop-new admission has no retry Task/pending payload queue. Monitors release
  leases on forced death. Metrics identify logical endpoints; sends count actual
  supported-transport outcomes rather than handler termination.
- **U3/B1:** socket owners stay responsive with one active receive credit and a
  fixed starter. Suspend retains the socket, port and memberships; admitted
  handlers can reply. Stop uses one absolute drain deadline before forced cleanup.
  Real ancillary data and local binding information remain separate.
- **M1/M2:** repeatable/raw options and operation order survive normalization;
  host desired memberships reduce startup add/drop order, remain idempotent and
  restore after generation restart. IPv4/IPv6 group, interface, egress, scope,
  loopback and hop settings have public APIs and actual network evidence.
- **C1/T1:** clients check sends, validate explicit interfaces, bound collection
  count/bytes/deadline and return partial errors. Affected network tests assert
  exchanged packets. No receive timeout or unsupported option becomes success.

Datagrams remain datagrams, including zero bytes. Ordinary continuation does not
route the next peer packet to the same handler. Stateless examples close
explicitly; legacy broadcast cleanup preserves returned state. Persistent
routing remains opt-in through the existing dispatcher, including empty writer
items and original writer receipt semantics. QUIC owns its protocol/CID state.

## Gate results

All evidence paths below are relative to `docs/udp-evidence/`. Exact CI commands
are also checked into the UDP workflows.

| Gate | Status | Evidence and practical scope |
|---|---|---|
| G1 Handler expiry/state/memory | PASS | `accounting-early-timer-green.log`, `accounting-early-timer-otp27.log`, final suite; explicit stale/early tokens, bookkeeping, overrides and infinity. |
| G2 Admission/resource bounds | PASS | `stress-final.log`, `admission-ledger.log`, host tests; forced death, start failure/deadline, caller death, concurrent reservations and global ceiling. |
| G3 Pause/resume/drain/cleanup | PASS | Final host suite; admitted original-port delayed replies, empty/idle stop, single drain deadline, stalled custom startup and listener death. |
| G4 Options/memberships/rollback | PASS | Final option/membership tests; `membership-order-red.log` then `membership-order-green.log`, OS membership inspection and startup rollback. |
| G5 IPv4 broadcast | PASS | `network-final.log`; independent limited/directed two-peer exchange both directions, explicit egress and original-port replies. |
| G6 IPv4 multicast | PASS | `network-final.log`; two groups/subscribers/interfaces, leave/rejoin epoch barriers, explicit egress, received TTL 3 and local/remote loopback distinctions. |
| G7 IPv6 multicast (Linux inet) | PASS | `network-final.log`; two groups/subscribers/interfaces, index/scope, leave/rejoin, received hop limit 5 and loopback distinctions. |
| G7 Scoped IPv6 send (socket backend) | BLOCKED | OTP `gen_udp_socket` rejects scoped sockaddr maps. Explicit unsupported-capability error; no scope-dropping tuple fallback. IPv6 membership/kernel controls are separately tested. See `udp-otp-multicast-defects.md`. |
| G8 Packet integrity | PASS | Final suite and fixture; empty/distinct packets, full datagram buffers before size enforcement, below/at/above bounds, large packets and ancillary forms. |
| G9 Client limits/errors | PASS | Final client suite; checked oversized send, missing interface, count/byte limits, partial errors, absolute deadline, readiness and socket cleanup. |
| G10 Endpoint isolation | PASS | `mixed-isolation.log`, final suite; same-handler independent metrics, simultaneous loopback unicast/broadcast/multicast, saturated/crashing endpoint and unaffected original-port replies. |
| G11 Existing/independent consumers | PASS | Final suite, `quic-current-final.log`, `independent-consumers-final.log`; UDP without QUIC, DHCP NIF, dispatcher and actual locked QUIC/TLS versions. |
| Warnings-as-errors compilation | PASS | `compile-final.log`; `mix compile --warnings-as-errors`. |
| Format | PASS | `format-final.log`; `mix format --check-formatted`. |
| Full tests including integration | PASS | `full-tests-final.log`; 3 doctests and 573 tests, zero failures. |
| Dialyzer | PASS | `dialyzer-final.log`; zero errors. |
| Focused strict Credo | PASS | Newly authored host, config, transport and client production modules; `credo-focused-final.log` uses exact per-file commands. |
| Whole strict Credo | FAIL | `credo-final.log`; retained pre-existing style/complexity/Logger findings, listed below. No all-green CI claim. |
| Linux OTP 27 portable/host matrix | PASS | `accounting-ci-otp27-final.log`, `otp27-linux-final.log`; 131 portable tests (three integrations excluded) and 60 Linux tests; commands from `.github/workflows/udp-regressions.yml`, isolated devenv build. |
| macOS portable matrix | NOT RUN | Runnable `macos-14`/OTP28 job supplied; no local macOS runner. Linux results do not verify macOS. |
| Minimum Elixir 1.13/older OTP range | NOT RUN | Project requirement remains unchanged. Scoped IPv6 sockaddr sends require OTP 24.3+. OTP27/28 evidence does not validate all older runtimes. |
| Remote CI | NOT RUN | Workflows supplied; no push or workflow dispatch. |

## Commands and measurements

Run from the repository root after preparing its locked dependencies:

```sh
mix compile --warnings-as-errors
mix format --check-formatted
mix test --include integration --no-cover
mix dialyzer
mix credo --strict
python3 scripts/udp/network_fixture.py
mix run scripts/udp/stress.exs
scripts/phase1/check.sh
scripts/phase1/independent_check.sh
```

The test alias adds coverage by default; `--no-cover` disables the unrelated
whole-project threshold for behavioral runs. Scoped CI tests instead export
coverage using `--cover --export-coverage NAME`. The final suite has 573 tests and three doctests, zero failures; slow tags remain excluded by repository defaults. Final seeds and command exit statuses are recorded in the raw logs and `final-results.log`. Exact scoped OTP27 commands are included in `runtime-commands.log`.

Stress offers 20 epochs of 202 datagrams (4,040 total), each 996 bytes, with a
handler ceiling of two and `max_packet_size: 1024`. Readiness proves both
controlled handlers are active before each 200-packet burst. It measures live
process count, receive-owner mailbox length and status high-water values at
barriers, then drains/stops each instance. Observations are samples, not a claim
that every transient kernel allocation was measured. Process baseline/final is
117/117, peak 125; mailbox peak 1, retained start payload peak 996 bytes, active
peak 2, pending count/bytes zero. Explicit drops are logged per run; OS queue
loss remains unmeasured. OTP27 independently returned from 115 to 115 processes, peak 123, retained 996 bytes and mailbox peak 1 (`accounting-ci-otp27-stress.log`). The same command is included in the OTP matrix.

The wire fixture creates four uniquely named isolated namespaces: three endpoint
namespaces (Abyss and two independent Python standard-library peers) and one
bridge namespace, with two separate bridged subnets. It uses 192.0.2.0/24,
198.51.100.0/24, private IPv6 prefixes, groups 239.192.74.1/2 and ff02::114/115,
high unprivileged ports, payload sizes 0, 6 and 42–63 bytes at low rates, unique epoch IDs and explicit readiness
barriers. Privilege is confined to namespace/link setup, entry and teardown;
participants run as the invoking uid/gid. Fixture-owned resources are removed
in `finally`; no ambient route/interface is changed. The mandatory Linux CI
job treats missing setup as failure. `network-final.log` has all 14 gates;
`network-socket-final.log` records nine supported wire gates plus the explicit scoped-error gate as `PASS_SUPPORTED_SUBSET`, and labels IPv6 scoped wire unsupported. CI runs an explicit backend matrix; it does not label the socket subset full IPv6 acceptance.

Independent current QUIC tests use aioquic 1.2.0 and verify provenance, 1 MiB
bidirectional/unidirectional echo and collection, opaque controls, invalid TLS/
ALPN, Retry faults, connection isolation, callback failures/timeouts, suspended
listener writer progress and writer-death restart. Copied outside-checkout
consumers build a release and prove UDP starts without loading the engine.
These consumer scripts finished before the final UDP-specific timer/membership and socket-option corrections; those corrections were validated in the final suite and fixture. Their logs can include intentional fault-test process exits and an initial
release RPC readiness miss; the scripts completed with exit zero and explicit
final PASS markers. The later changes preserve the default inet tuple-send path used by QUIC and ordinary UDP consumers; the shared Writer/QUIC-host changes were already included in those consumer runs.

## Limits and remaining environment work

- The admission bound covers network ingress and supported APIs, not arbitrary
  messages injected by hostile local processes. Kernel queues are separate from
  the zero-item user-space pending queue. One active credit can temporarily retain
  one complete UDP packet up to the receive buffer (65,536 bytes) before size
  validation; only its admitted startup payload is capped by max_packet_size.
  The retained status high-water measures that reservation, not total BEAM memory. A timed-out start frees its payload but
  keeps an empty busy reservation until startup resolves or shutdown kills it.
- Memory checks are sampled process bytes; callback stalls, shared binaries and
  inter-sample peaks prevent a strict total-memory guarantee.
- Suspend discards packets actually received while suspended. Kernel-queued
  packets may arrive after resume; it is an admission barrier, not a kernel flush.
- Dispatcher/QUIC stop is host cleanup, not a claim of application-session
  graceful completion. QUIC draining was not redesigned.
- Linux multicast controls use tested native option mappings. IPv6 controls on
  other platforms and scoped sockaddr sends on the socket backend fail
  explicitly. Strict per-group filtering is supported only on Linux IPv4 inet;
  strict IPv6/socket-backend/macOS requests fail explicitly.
- Membership interface alone does not guarantee per-interface wildcard filtering
  on Linux IPv6. The fixture uses independently device-bound observers where
  that stronger distinction is required. No payload deduplication hides delivery.
- Explicit unicast/broadcast device egress is Linux-specific and can require
  privilege; OS errors are preserved. Destination/interface metadata is limited
  to fields actually returned by OTP. Wildcard sockname is never invented as a
  received destination. Native inet can ignore unsupported arbitrary raw options.
- Whole strict Credo exits 30 with 15 warnings, 15 refactoring opportunities, 48 readability issues and five design suggestions. It retains legacy Handler quote length, QUIC complexity/nesting/
  apply/alias style, Dispatcher module/try/nesting style, legacy server/pool try
  style, Logger metadata configuration, support/test style and numeric literals.
  Those existing findings are not hidden or fixed by unrelated refactoring.
- Remaining environment gates are macOS, the minimum-runtime range, remote CI
  and any future OTP scoped socket-backend support. No listed organization
  dependency needed a repository-local workaround or upstream internal request.

The protocol-neutral multicast example exchanged a query (`example.log`), and the public broadcast CLI receiver/query exchanged `example-broadcast` over the loopback broadcast address (`example-broadcast-final.log`), with readiness before sending. Misleading README multicast-interface recipes were replaced with the tested membership guide and these examples.

Use `udp-broadcast-multicast.md` for public configuration and the capability
matrix, and `scripts/udp/README.md` for fixture setup and supported backend runs.
