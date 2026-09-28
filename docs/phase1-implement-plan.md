# Phase 1 implementation plan

Date: 2026-09-28. Scope: this repository only. DNS/DoQ and HTTP/3/QPACK
permanently belong to independent application servers, never to Abyss.
The user-owned `03-abyss-plan.md` is preserved unchanged.

## Baseline and prerequisites

- Review baseline: `37cda667a4af0036e5ac1de7817fc8f0f19fff82`.
- Actual initial HEAD: `21c76accfa1478f84344200ffa72e846ec9e3006`, initially `main`.
- Work branch: `codex/phase1-quic-service`, reusing the existing checkout.
- Initial changes: only untracked `03-abyss-plan.md`, SHA-256
  `9b520c0248efbb997bb83c68c04d11d9995f4c7742f7fecad1a6bf274d60284f`.
- Elixir 1.18.5 / OTP 28.5.0.5 / ERTS 16.4.0.5.
- G-T source: `gsmlg-dev/ex_quic@27779b72da0c784787142012fee3e229fe5397df`.
  Its consumer/I/O contracts and adapter were inspected read-only; GitHub's
  main ref resolves to this full revision.
- G-S source: `gsmlg-dev/ex_ssl@f1327e0bb7fb2093b8dc2b07e72b26233a739963`,
  pinned by G-T. The adjacent ex_ssl HEAD is
  `fb47051355c9d0a29caee046fa060a745ad0ce5b`; it is not the dependency pin.
- Both upstream acceptance reports mark their scoped gates PASS. This is
  prerequisite evidence, not Abyss network acceptance.

## Ordered implementation and verification

1. **A-00 — service contract.** Add a small optional-backend facade, validated
   configuration, supervised socket owner and isolated per-connection consumers.
   Reuse the existing writer and public QUIC operations. Verify missing backend,
   invalid configuration, attachment order and consumer isolation with regressions.
2. **A-01 — writer.** Reserve item/byte credit before payload admission; retain
   credit through actual completion; distinguish send admission, completion and
   unknown outcomes. Bound result/waiter retention. Verify with deterministic
   suspended-writer and blocked-send barriers before fixes.
3. **A-02 — lifecycle.** Fail closed on host component death; bounded teardown,
   single socket owner, generation invalidation and connection-local consumer
   failure. Verify lifecycle races independently of real TLS acceptance.
4. **A-03 — independent applications.** Standalone echo and collection applications
   use custom ALPNs and the public facade. Fetch immutable upstream Git sources and
   exercise real UDP/QUIC using pinned aioquic 1.2.0; never count fake backends as
   interoperability. Record every requested scenario separately.
5. **A-04 — optional activation and regressions.** Compile and start ordinary UDP
   without ex_quic and build/start an independent QUIC release with it. Keep the
   existing transports and Rust NIF. Run only relevant tests and report unrelated
   failures without repairing them.

## Ownership and implementation choices

`QUIC.Endpoint` alone owns CIDs and protocol state. The new service owns a passive
UDP socket and one blocking receiver, an independent writer, and consumer workers.
Application code never runs on shared ingress/egress paths. A handler is chosen
by listener configuration; TLS negotiates the application's opaque ALPN list.
Connection and stream handles remain the engine's opaque generation capabilities.

Core resolves the supported `QUIC` module at runtime, with no static optional
struct expansion or new core dependency. Consumer projects explicitly declare
ex_quic. Ordinary UDP does not load it. Tests inject a private fake backend only for
host lifecycle regression coverage. Streams are bytes, FIN is directional, and
application error codes are delegated unchanged.

Do not publish or invent a fix revision. The acceptance document must distinguish
PASS, FAIL, BLOCKED and NOT RUN and identify all uncommitted artifacts. G-A cannot
pass on writer or mock tests alone.

## Completion checklist

- [x] A-00: public supervised service and isolated handler binding.
- [x] A-01: pre-mailbox item/byte admission and bounded completion bookkeeping.
- [x] A-02: bounded drain, host failure teardown and generation regressions.
- [x] A-03: independent handlers and pinned-peer network matrix.
- [x] A-04: optional activation, ordinary UDP and production release checks.

All changes remain uncommitted. See [phase1-acceptance.md](phase1-acceptance.md)
for exact commands, results, remaining limits and the G-A decision. This checklist
does not extend acceptance to the excluded application protocols or capabilities.
