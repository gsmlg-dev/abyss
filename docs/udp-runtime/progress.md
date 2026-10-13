# UDP runtime execution progress

## Source and authorization

- Baseline: `9b710e6480900e16e304f40e63623aff8c922e19`, main.
- Execution: `codex/udp-runtime`, `.trees/udp-runtime`.
- Original dirty files: three user-supplied `abyss-udp-*` Markdown files; preserved, excluded from implementation commits.
- User explicitly authorized implementation P0–P6, commits, push and next minor release (0.8.0); this supersedes remote/release prohibitions in supplied documents.
- Runtime: NixOS Linux x86_64; devenv Elixir 1.18.4 / OTP 27 / ERTS 15.2.7.4; system Elixir 1.18.5 / OTP 28 / ERTS 16.4.0.5.
- Full plan (427 lines) and prompt (138 lines) read. No sibling edits.

## Findings

| Finding | Applicability at baseline | Action |
|---|---|---|
| F1 | Applies: Client single_exchange and UDP.send_recv accept first peer | P1 exact resolved peer and absolute deadline regressions |
| F2 | Applies: pre-open checks inspect explicit backend only | P1 shared effective resolver and fresh-VM boot tests |
| F3 | Applies: callback tuple, metadata in telemetry only | P2 immutable Datagram |
| F4 | Applies: broadcast one-shot, continue retains original invocation process | Preserve legacy; explicit new policies P3 |
| F5 | Applies: rejects broadcast=true, permits Multicast/membership with false | Preserve tested combinations and document matrix |
| F6 | Applies: root Rustler and DHCP-specific NIF | P5 explicit optional-package migration |

## Compatibility inventory

Legacy Abyss.start_link/child_spec/suspend/resume/stop/join/leave/memberships; custom start_link and new_connection messages; Handler handle_data tuple/state, continue and broadcast completion; UDP/Unicast/Broadcast/Multicast transports and Core send forms; Client single and multi-peer collectors; Dispatcher.SendCapability, Writer admission/receipt/await outcomes; optional QUIC service with engine-owned CIDs; DHCP Native five functions and dhcp_rx/arp_rx/down messages. Existing ownership remains Listener, membership storage and global admission remain TableOwner.

## Phase checklist

- [x] P0 baseline tests/lint and consumer inventory (G0 PASS)
- [x] P1 peer/backend corrections (226 scoped tests PASS; five fresh VMs each OTP27/28 PASS)
- [x] P2 contracts/GenUDP consumer/legacy compatibility (64 contract/native tests + 3 doctests PASS; real GenUDP runtime exercised)
- [x] P3 three policies/bounded effects/lifecycle (protected helper/worker DOWN accounting and bounded stress PASS)
- [x] P4 direct socket metadata/strict egress/wire fixtures (18 OTP27/28 × backend × policy runs PASS)
- [x] P5 optional DHCP extraction/clean consumers (OTP27/28 core no-Rust and optional 11 wire gates PASS)
- [ ] P6 QA/matrices/consumers/docs/performance
- [ ] Commit/push/release and published consumer verification

## Evidence and reproduction

Run in primary checkout: `devenv shell -- mix test --include integration --no-cover` and `devenv shell -- mix credo --strict`; raw baseline logs copied into `evidence/`. Strict Credo baseline has 15 warnings, 15 refactor findings, 48 readability findings, 5 design suggestions; unrelated cleanup is out of scope. Runtime identity in `evidence/baseline-runtime.log`. Root and examples lockfiles inspected; optional QUIC consumer versions remain locked.

## Current work / exact next action

Baseline suite PASS: 3 doctests, 573 tests, zero failures, exit 0. Strict Credo FAIL pre-existing, exit 30, 83 findings. Implement P1 regressions and contract design. Keep this document updated at every checkpoint; do not describe historical logs as new acceptance. All G0–G10 currently pending.

Checkpoint: new worker/coordinator files and Listener integration implemented. Next: collect p3-tests.log, repair deterministic failures; native adapter agent owns native.ex and native tests. P1 agent owns Client/UDP/Core/Multicast/Unicast. Root owns Listener/runtime/writer/shared ledger. OTP27 GenUDP socket symbolic receive TTL/TOS options unavailable; native capability separate.

P3 checkpoint: real UDP tests for per-datagram/endpoint/keyed, empty payloads, same-key ordering/independent-key progress, invalid action atomic validation, delayed managed events, blocked init/callback/control/stop, overload and legacy Handler/membership/host regression: 33 tests PASS, evidence p3-tests.log. Cleanup credit now remains reserved until hook completion/watchdog; no task per dropped packet. Additional resource/failure coverage remains before G3/G7 acceptance. Baseline legacy stress captured independently on original source: processes115 -> high123 -> final115, admitted high2, owner mailbox high1, retained startup996; counters sampled, kernel drops unmeasured.

P1 checkpoint: exact-peer/absolute deadline helpers Client/UDP/Unicast and cached public-probe effective backend resolver implemented; p1 logs include red regressions, green source hashes, and fresh VM backend matrix. P3 expanded lifecycle regressions 15 tests PASS; blocked-writer/credit tests added next. Native owner arm integration implemented; first end-to-end startup exposed unsupported OTP recvbuf mapping (agent correcting) and fixture existing-atom policy parsing (fixed). No gate accepts a failed wire run.

## Resumption checkpoint (2026-10-13)

- Latest P3: 36 focused runtime/dispatcher tests PASS, `evidence/p3-tests.log`. Forced Writer/Admission cleanup and linked route/effect helpers repaired; reservations retained until Worker DOWN. Independent effect-helper DOWN accounting review is assigned.
- Latest P4: 20 Linux native isolated multi-interface gates PASS on OTP27, `evidence/p4-wire-otp27.log`. Fixture reads actual interface indices independently (never assumes namespace index values). Native/contract tests: 64 tests + 3 doctests PASS; public IPv4/IPv6 strict replies PASS.
- P5 gate satisfied: optional-package agent authorized to stage both consumers before extraction. Optional package remains unpublished. DHCP restricted-capability fixture imports existing isolated namespace Fixture.
- Current ownership: root Listener/fixtures/CI/docs/integration; p2 agent Runtime/Worker/Actions/runtime tests; p1 agent DHCP package/shim/root native packaging metadata. Preserve concurrent edits.
- Exact next actions: run OTP28 native tests/wire; OTP27 GenUDP inet/socket and new execution wire matrix; collect P3 review and P5 staged consumer gates; then full QA/independent QUIC/performance, docs, commit/push/release0.8.0. No remote mutations yet.

Checkpoint: OTP28 native20 wire gates PASS; OTP27 GenUDP inet14/socket10 supported-subset gates PASS; new API per_datagram/endpoint/keyed each14 family gates PASS. Added required capability startup and metadata admission checks (4 tests PASS); Listener strict lint PASS. P5 staged/final OTP27 core no-Rust and optional11 DHCP/ARP gates PASS, OTP28 pending. P3 forced-death shared-ledger protection work in progress. QUIC candidate concurrent network gate failed by independent-peer deadline; baseline reproduction first hit stale OTP28 BEAM cache, fresh isolated OTP27 build in progress. Do not publish until assessed.

Checkpoint: P3 protected-work/lifecycle tests24 PASS; zero-input runtime death now kills blocked Writer/Admission with observed DOWN. Grouped the seven new internal datagram settings into `ServerConfig.datagram_options`; all public flat startup options and legacy struct fields retained. Grouped config/runtime/admission/dispatcher/requirements53 tests PASS, final Dialyzer PASS0warnings. OTP28 full643+3doctests PASS; first OTP27 concurrent full642+3doctests had100ms Dispatcher writer-death timeout, scoped later PASS; final serial rerun required. Full Credo baseline83 + one new config-size warning identified and eliminated by grouping, final comparison pending. Optional packaged consumers OTP27/28 PASS. Independent UDP/single QUIC echo/outside collect PASS; existing simultaneous QUIC test fails on baseline and direct engine too (diagnosis in progress; no workaround/changed timeout). Native new endpoint/keyed each21 wire gates PASS. Exact next action: final lint/format and serial OTP27 full; final matrices/performance and QUIC investigation; then acceptance/doc/commit/push, release only on accepted mandatory gates.


## Active checkpoint after integration review

- Public flat new options retained; internal seven settings grouped in `ServerConfig.datagram_options`. Duplicate scalar selection consistently follows first keyword occurrence. New handlers require finite positive egress item/byte quotas. Custom transports report unverified capabilities; IPv4 scoped send has explicit family reason.
- Final wire matrix: OTP27/28 × inet/socket/native × per_datagram/endpoint/keyed = 18 PASS runs. Inet 15, socket 10 supported-subset, native 21 gates per run. Socket backend scoped IPv6 remains explicitly unavailable. `evidence/p6-wire-matrix.json` and `final-wire-*` logs.
- P5 fresh package-content consumers both runtimes PASS; optional package unpublished. Core no Rust/Cargo/NIF/QUIC, optional 11 DHCP/ARP wire gates, Rust unit tests and Clippy PASS.
- P6 earlier OTP28 full643+3doctests PASS. Current OTP27 diagnostic full646+3doctests seed91644 PASS, seed953627 has legacy post-receive telemetry assertion race under investigation. Earlier writer-death100ms assertions failed on two full runs; current diagnostics did not reproduce. Keep failed logs; no timeout/assertion weakening.
- Full Dialyzer zero errors; strict Credo baseline83/current83/new0 before latest capability reason change. Listener complexity introduced by that change now factored into helper, final check pending.
- Actual runtime stress: all3 policies ×5epochs PASS, baseline/final processes116, bounded input8/7160bytes and egress4/2048bytes; offered1320 UDP/policy, admitted40, drops1280, direct180/rejected160, actual replies60. These are host-managed bounds and sampled high-water values.
- **G8 / release BLOCKED:** unchanged simultaneous optional QUIC consumer fails on baseline and candidate; direct `Quic.listen` reproduces `:ack_range_limit`. Runtime tracing attributes it to `Quic.Recovery.note_received/3`, application packet2803, retained256 ranges/max256. Upstream package source `gsmlg-dev/http_fetch/apps/elixir_quic`. Agent p1 owns latest published consumer check, typed upstream Bug and runnable reproducer. No dependency workaround or changed consumer workload authorized.
- Agent p2 owns bounded Writer-death diagnostics and removal of temporary test instrumentation. Root owns final QA/docs/controlled paired performance and branch commit/push. Release cannot proceed until genuine upstream resolution and mandatory unchanged consumers pass.
- Exact next actions: finish diagnostics, freeze implementation, run final full QA and controlled paired measurements, record G0–G10 in acceptance.md, file/link upstream blocker/TODO, commit and push tested checkpoint. Preserve all user-supplied documents. Do not bump/publish0.8.0 while G8 unaccepted.


Checkpoint: upstream blocker is now filed/verified OPEN Bug/internal request as gsmlg-dev/http_fetch#108. Latest0.21.5 disposable unchanged workload also FAIL; direct runnable `scripts/phase1/ack_range_repro.exs` preserves original peer deadline and engine-only reproduction. Added required upstream TODO at engine ingress. No optional-consumer locks changed. Latest final-format/dev+test compile/Dialyzer/diff all PASS (`p6-final-qa.log`); Credo83/83/new0 (`p6-credo-frozen-comparison.log`). OTP27 frozen953627646+3 PASS. OTP28 same run exposed two test synchronization gaps, agent repairing barriers with unchanged loads/quotas/assertions, no production workaround. Serial3paired steady baseline/current medians9834/9194exchanges per second, latency101/107us; raw6logs and JSON preserved,6.5% throughput regression reported (older concurrent samples not comparisons). Root acceptance draft created; controlled new-policy samples/full reruns/branch CI remain.


Selected-source checkpoint: final full OTP27/28 seed953627 each646tests+3doctests PASS (`p6-full-otp27-selected.log`, OTP28 equivalent). Two test-only synchronization repairs validated40checks each runtime, unchanged payloads/quotas/timeouts. Mandatory TODO at engine ingress adds one Credo TagTODO finding:baseline83/current84/new1; no suppression. G10 BLOCKED until upstream108/TODO resolved, while format/dev+test strictcompile/Dialyzer/diff PASS. Controlled new-policy3samples each PASS:per_datagram3198/s,endpoint3546/s,keyed3111/s, medians304/276/314us; material overhead versus legacy reported, no improvement claim. Initial fresh-VM benchmark mode parse failed before traffic because atom was not loaded; explicit finite policy map fixed script; all9samples now PASS. Acceptance.md/performance.md completed for local gates; next commit/push candidate and dispatch regression+wire workflows for actual macOS/remote selected-source evidence. Release still blocked; version unchanged0.7.0.

Commit checkpoint: selected-source151file SHA256manifest verified; final examples and native IPv4/IPv6 strict reply smoke PASS. Raw evidence tool formatting preserved through scoped .gitattributes (source whitespace checks unchanged), staged diff check PASS. User inputs/deps/build/native artifacts excluded from staging. Preparing authorized branch commit/push; upstream108still OPEN and release BLOCKED.
