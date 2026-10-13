# UDP runtime acceptance checkpoint

This is the unreleased 0.8 candidate, not a publication report. P0–P5 are implemented and accepted on the tested Linux environments. P6 is incomplete because the mandatory unchanged concurrent QUIC consumer fails. Do not publish until G8 is accepted.

## Source and environment

Baseline `9b710e6480900e16e304f40e63623aff8c922e19`, package 0.7.0. Candidate branch `codex/udp-runtime`, worktree `.trees/udp-runtime`. User-supplied plan/prompt files are preserved and excluded from commits. User explicitly authorized commit, push and next minor release; the extracted optional DHCP package remains intentionally unpublished.

Linux NixOS x86_64, Elixir 1.18.4 / OTP 27 / ERTS 15.2.7.4 in devenv; system Elixir 1.18.5 / OTP 28 / ERTS 16.4.0.5. Tests use locked dependencies. Native adapter requires Linux OTP27+, ordinary GenUDP does not claim an untested higher minimum. Root Elixir `~> 1.13` requirement is unchanged and the actual minimum remains unverified. No ambient LAN or sibling repository was modified.

Final implementation hashes and commands are recorded in `evidence/final-source-sha256.log` and `evidence/final-source-identity.json`. Earlier phase evidence covers its named checkpoint; final local/remote results below reconcile the selected source. Raw logs include failed attempts and unsupported-feature results, not fabricated PASS labels.

## G0–G10

| Gate | Status | Reproducible evidence and limits |
|---|---|---|
| G0 Baseline | PASS | `baseline-runtime.log`, `baseline-tests.log`:573 tests+3 doctests,0 failures. `baseline-credo.json`:83 pre-existing findings,exit 30. [Progress](progress.md) records F1–F6 and legacy API inventory. |
| G1 Correctness | PASS | `p1-red-peer.log`, `p1-red-backend.log`, `p1-red-idempotence.log` distinguish baseline defects. `p1-green-otp27.log`:226 scoped tests. `p1-backend-otp27.log`/`p1-backend-otp28.log`:five fresh BEAM instances per runtime verify omitted/default/explicit driver choices through actual service/client paths. |
| G2 Public contracts | PASS | `p2-contracts.log`, final full suite and `final-wire-*`:real GenUDP/new API consumers, legacy/custom handlers, empty packets, sampling-independent metadata. Datagram/handler/context contain no fake destination or raw native handle disguised as GenUDP. |
| G3 Execution/effects | PASS | `p3-retained-work-tests.log`:24 protected-lifecycle tests. Public three-policy wire matrix and `p6-runtime-stress-final.log`:bounded admission/effects, serialized same-key ordering, independent-key progress, watchdogs, last returned state and no replay. [Design](design.md) scopes ordering/outcomes. |
| G4 Receive metadata | PASS | `final-wire-otp27-native-*.log` and OTP28 equivalents:21 independent-peer gates/run; IPv4/IPv6 two groups/two interfaces, identical payloads with distinct destinations, actual index/scope, broadcast ingress. `test/abyss/transport/native_test.exs` tests actual `:trunc`/`:ctrunc`, unsafe metadata clearing and retained sub-binary copies; included in full suite. |
| G5 Egress | PASS | Same native 21-gate logs verify actual original-socket source/interface/port and two link-local scopes. Inet 15 gates/run verifies scoped sending. GenUDP socket 10 gates/run explicitly returns unavailable scoped-send capability; this rejection does not establish scoped-send support. Strict missing metadata rejects; no routed/new-socket fallback. |
| G6 Packaging | PASS | `p5-final-consumers-otp27.log`/OTP28:archive-content clean no-Rust/no-QUIC core consumer and explicitly installed optional NIF consumer,11 DHCP/ARP wire gates each. Independent package 3 tests each, Rust 5 ARP tests, locked Clippy and source integrity PASS. [P5 notes](p5-notes.md) document direct resource return and explicit migration; package unpublished. |
| G7 Lifecycle/resources | PASS | Protected helper/worker DOWN accounting, component death, caller death, generation invalidation, accepted egress/stop deadlines and membership restoration in full/scoped suites. `p6-runtime-stress-final.log`:three policies×five epochs,116 baseline/final processes, retained/input/egress within quotas. [Performance](performance.md) states sampled limits and kernel-drop uncertainty. |
| G8 Existing consumers | BLOCKED | Legacy UDP/Dispatcher/receipt regressions and `p6-independent-check.log` pass. Unchanged simultaneous locked QUIC gate FAILS on baseline and candidate; direct `Quic.listen` bypasses Abyss and fails `:ack_range_limit`. [Upstream Bug #108](https://github.com/gsmlg-dev/http_fetch/issues/108), severity blocker. No local workaround or workload/timeout change. |
| G9 Runtime/backend matrix | FAIL | Local Linux OTP27/28×inet/socket/native×three policies:18 PASS runs, `p6-wire-matrix.json`. Inet 15/native 21/socket 10 supported-subset gates per run. Initial macOS portable run has three wrong-IP fixture bind failures (`eaddrnotavail` for unconfigured127.0.0.2); explicit CI loopback alias setup/cleanup repair pending final rerun; actual minimum runtime explicitly unverified. No macOS native claim. |
| G10 QA/handoff | BLOCKED | Full selected-source tests/format/compile/Dialyzer pass; the required upstream TODO remains one new lint finding until issue 108 is resolved. Baseline strict Credo 83; candidate 84 with one required upstream TODO; absolute lint remains FAIL exit 30. README/examples/design/migration/progress and reproducible diagnostics included. No overall completion or release claim. |

All evidence paths in this table are relative to [evidence/](evidence/).

## Commands

From the primary checkout, run OTP27 candidate commands through:

```sh
devenv shell -- bash -c 'cd .trees/udp-runtime && <command>'
```

From the candidate worktree, system OTP28 uses `MIX_BUILD_PATH=/tmp/abyss-p6-otp28 ERL_FLAGS='+S 8:8' <command>` so BEAM artifacts from different OTPs are isolated. Do not overwrite user-owned baseline PLTs. Common commands:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
MIX_ENV=test mix compile --warnings-as-errors
mix test --include integration --no-cover --seed 953627
mix dialyzer
mix credo --strict --format json
git diff --check
bash scripts/udp/backend_boot.sh
mix run example/datagram_echo.exs
mix run scripts/udp/runtime_smoke.exs
mix run scripts/udp/stress.exs
mix run scripts/udp/runtime_stress.exs
python3 scripts/udp/p5_consumers.py
```

Each backend/policy wire run uses the actual fixture, not mocks:

```sh
ABYSS_UDP_BACKEND=native ABYSS_UDP_API=datagram ABYSS_UDP_EXECUTION=keyed   python3 scripts/udp/network_fixture.py
```

Repeat independently with `inet|socket|native`, `per_datagram|endpoint|keyed`, and both runtimes. Fixture setup requires Linux `ip`, `setpriv` and passwordless sudo. Code/peers run as the invoking user within fixture-owned disposable namespaces; independent peers read actual interface indices. Exit 77 means BLOCKED, not PASS. Setup/teardown never alters ambient routing/memberships. `p6-wire-matrix.json` records per-run result/gate counts; socket supported-subset restrictions remain explicit.

P5 creates fresh archive-content consumers outside the checkout and hides Cargo/Rust for core. Namespace-only CAP_NET_RAW/CAP_NET_BIND_SERVICE is retained for optional wire tests. Source preservation, unit/source tests and native reclamation limitations are described in P5 notes.

## Mandatory upstream blocker

Original `elixir_quic/ex_ssl ==0.17.0` consumers remain locked. Run unchanged checks through OTP27:

```sh
bash scripts/phase1/check.sh
bash scripts/phase1/independent_check.sh
cd examples/quic_echo
ERL_FLAGS='+S 8:8' mix run --no-compile --no-deps-check --no-start   ../../scripts/phase1/ack_range_repro.exs
```

`check.sh` FAILS the original simultaneous two-echo/one-collector workload at the original 25-second deadline. The 1 MiB collector passes; independent single echo/collect/no-QUIC checks pass. Fresh original baseline also fails the concurrent workload (`baseline-quic-fresh.log`). Disposable published 0.21.4 and 0.21.5 consumers also fail without changing the workload (`p6-quic-0214.log`, `p6-quic-0215.log`); neither dependency nor consumer lockfile was upgraded.

The direct reproducer starts only the engine and original echo algorithm/independent peers. Both connections close `:ack_range_limit`, endpoint reports the same `last_error`, routes/admission_drops 0 (`p6-quic-ack-range-repro.log`). Return tracing separately identifies `Quic.Recovery.note_received/3` failing at application packet 2803 with 256 retained/max ranges (`p6-quic-direct-trace.log`). Tracing adds overhead; untraced wire failure remains primary evidence. Deterministic sparse receive history in the script reproduces exhaustion at range 257. Upstream source is `gsmlg-dev/http_fetch/apps/elixir_quic`; issue 108 is verified OPEN, type Bug, label `internal request`, severity blocker (`p6-quic-upstream-issue.log`). TODO is attached to the actual engine ingress callsite.

Next required action: resolve upstream receive-history retention, update the optional consumers to a genuinely fixed published dependency, and rerun unchanged mandatory consumers. Per repository blocker policy, no local limit increase, weakened assertions or changed concurrency is permitted. Version bump/tag/publication 0.8.0 remains BLOCKED. Ordinary UDP implementation can be reviewed from the pushed candidate branch.

## Failures retained and reconciliation

Baseline full 573+3 passes; strict lint has 83 existing findings. Candidate older full OTP27 runs exposed Dispatcher writer-death 100 ms timeouts; later diagnostic runs at both failing seeds passed that unchanged assertion, so its earlier cause remains unproven and logs remain. Candidate diagnostic 953627 also exposed post-wire telemetry sampling before sender accounting; test now observes exact wire replies and monitored handler completion before unchanged metric assertions.

Latest initial OTP28 full 646+3 had two failed synchronization assumptions: a send could complete before the next reservation, and a just-sent UDP packet was not confirmed admitted before pause/death. Tests now pin the first send in flight and observe the queued admission before death, retaining original payloads/limits/assertions. No production workaround is applied. Final reruns must pass and are recorded below; earlier failures remain evidence.

## Final selected-source results

- Selected source: `final-source-sha256.log`/`final-source-identity.json` (implementation, tests, config, fixtures, workflows, package sources; generated evidence excluded).
- OTP27 full:646 tests + 3 doctests, 0 failures, exit 0 (`p6-full-otp27-selected.log`); same seed 953627.
- OTP28 full:646 tests + 3 doctests, 0 failures, exit 0 (`p6-full-otp28-selected.log`); same seed 953627, separate build path.
- Format/dev+test strict compile PASS (`p6-build-selected.log`, `p6-final-examples-qa.log`). Dialyzer 0 errors/0 skips PASS (`p6-dialyzer-selected.log`); final staged diff check PASS. Raw `.log` tool output preserves its original whitespace via scoped `.gitattributes`; source whitespace checks stay enabled.
- Strict Credo FAIL exit 30: baseline 83/current 84. Exactly one new finding is `Credo.Check.Design.TagTODO` for the required `# TODO(upstream): gsmlg-dev/http_fetch#108`; baseline comparison in `p6-credo-selected-comparison.log`. No lint check or threshold was disabled to hide it. G10 remains BLOCKED on this upstream TODO.
- Paired steady/resource comparisons completed, all actual exchanges/stress pass; measured regressions and exact commands in performance.md.
- Candidate commit e120451 pushed. Remote wire/package run38395163332 PASS all19jobs; regression run38395163655 Linux OTP27/28 PASS, initial macOS wrong-IP fixture FAIL. Final macOS fixture rerun pending. No main merge, version bump, tag, GitHub release, Hex publication or optional-package publication.

Current resumable checkpoint: progress.md. G8 and release are blocked by upstream 108; these successful independent UDP checks do not waive it.


Remote raw evidence: `p6-remote-wire.json`, `p6-remote-dhcp.log`, `p6-remote-regressions-initial.json`, `p6-remote-macos-initial.log`. Remote wire/package run https://github.com/gsmlg-dev/abyss/actions/runs/38395163332 tests committed sourcee120451. macOS initial3failures are fixture address provisioning, not an accepted portable result; all assertions remain in place.
