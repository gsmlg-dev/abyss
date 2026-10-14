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
| G3 Execution/effects | PASS | Completed-effects retirement regression RED then covered22/0 on OTP27/28; current full648+3 suites and stress PASS.  `p3-retained-work-tests.log`:24 protected-lifecycle tests. Public three-policy wire matrix and `p6-runtime-stress-stop-final.log`:bounded admission/effects, serialized same-key ordering, independent-key progress, watchdogs, last returned state and no replay. [Design](design.md) scopes ordering/outcomes. |
| G4 Receive metadata | PASS | `final-wire-otp27-native-*.log` and OTP28 equivalents:21 independent-peer gates/run; IPv4/IPv6 two groups/two interfaces, identical payloads with distinct destinations, actual index/scope, broadcast ingress. `test/abyss/transport/native_test.exs` tests actual `:trunc`/`:ctrunc`, unsafe metadata clearing and retained sub-binary copies; included in full suite. |
| G5 Egress | PASS | Same native 21-gate logs verify actual original-socket source/interface/port and two link-local scopes. Inet 15 gates/run verifies scoped sending. GenUDP socket 10 gates/run explicitly returns unavailable scoped-send capability; this rejection does not establish scoped-send support. Strict missing metadata rejects; no routed/new-socket fallback. |
| G6 Packaging | PASS | `p5-final-consumers-otp27.log`/OTP28:archive-content clean no-Rust/no-QUIC core consumer and explicitly installed optional NIF consumer,11 DHCP/ARP wire gates each. Independent package 3 tests each, Rust 5 ARP tests, locked Clippy and source integrity PASS. [P5 notes](p5-notes.md) document direct resource return and explicit migration; package unpublished. |
| G7 Lifecycle/resources | PASS | Final real-deadline red/green regression covers runtime protected-slot retirement before drain notification; covered runtime23/0 and full648+3 each OTP27/28 PASS. Original20msdeadline test preserved; running/suspended failure handling unchanged. Actual normal helperDOWN retires completed-effects watchdog without refund; queued expiry regression and current protected stress PASS.  Protected helper/worker DOWN accounting, component death, caller death, generation invalidation, accepted egress/stop deadlines and membership restoration in full/scoped suites. `p6-runtime-stress-stop-final.log`:three policies×five epochs,116 baseline/final processes, retained/input/egress within quotas. [Performance](performance.md) states sampled limits and kernel-drop uncertainty. |
| G8 Existing consumers | BLOCKED | Legacy UDP/Dispatcher/receipt regressions and `p6-independent-check.log` pass. Unchanged simultaneous locked QUIC gate FAILS on baseline and candidate; direct `Quic.listen` bypasses Abyss and fails `:ack_range_limit`. [Upstream Bug #108](https://github.com/gsmlg-dev/http_fetch/issues/108), severity blocker. No local workaround or workload/timeout change. |
| G9 Runtime/backend matrix | FAIL | Final stop-source network38404707197 all19jobsPASS, exact4645a5ec (`p6-remote-stop-network.json`, source-linked wire JSON/logs). Regression38404701185 Linux27/28PASS, macOS194tests1failure in new watchdog-order regression. Test-only actual-expiry/helperDOWN ordering repair locally23/0 each; actual final macOS rerun pending. Minimum Elixir explicitly unverified, no macOS native claim. |
| G10 QA/handoff | BLOCKED | Stop-source full tests/format/compile/Dialyzer pass; final watchdog-test source OTP28 full remains FAIL on unchanged Dispatcher writer-death100ms assertion under investigation; the required upstream TODO remains one new lint finding until issue 108 is resolved. Baseline strict Credo 83; candidate 84 with one required upstream TODO; absolute lint remains FAIL exit 30. README/examples/design/migration/progress and reproducible diagnostics included. No overall completion or release claim. |

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

- Selected source: `final-source-sha256.log`/`final-source-identity.json`,151 files, manifest `1c9b1fcd63aa2bf16c73cb57cd6e032a92004dd7131436ad9339cc9b955b71dd`. Production source identical to4645a5ec; final change only pins watchdog-test event ordering. Listener drain completion accepts actual expected runtime `:normal`/`:killed` while draining; all other failure modes retain prior handling.
- Stop-source OTP27/28 full each648+3/0 PASS (`p6-full-otp27-stop-final.log`, OTP28 equivalent). Final test-harness source OTP27648+3/0 PASS (`p6-full-otp27-watchdog-harness-final.log`); OTP28 full and serial rerun both fail unchanged Dispatcher writer-death100ms assertion, diagnostic investigation active. Watchdog regression PASS in all these runs. No timeout/assertion changed.
- Covered focused runtime each23 tests,0 failures (`p6-stop-deadline-green-otp27.log`, OTP28 equivalent). Actual same-deadline runtime/worker/Writer/Admission/server/listener DOWN observed. Expected red retained (`p6-stop-deadline-red-otp27.log`); original20msstop and blocked-writer tests unchanged.
- Production-source format/dev+test strictcompile/Dialyzer0errors0skips/examples/native strict IPv4/IPv6 reply PASS (`p6-stop-final-qa-otp27.log`). Actual stress three policies×five epochs PASS (`p6-runtime-stress-stop-final.log`).
- Strict Credo FAIL exit30, baseline83/current84/new1 sole required upstreamTODO (`p6-credo-stop-final-comparison.log`). No disabled lint check; G10 upstream-blocked.
- Current-source controlled15steady samples PASS; legacy medians10,082→9,391/s (−6.9%). New-policy3431/3736/3382/s; performance.md gives commands/limits. Previous samples retained with explicit historical source attribution.
- Final stop source committed/pushed `4645a5ec68049b067c9530a3f1ee670fb557a775`. Regression38404701185/network38404707197 and fresh finalOTP27archive consumers running; results pending. Prior9c92636 matrix evidence remains historical.
- No main merge, version bump, tag, GitHub release, Hex publication or optional-package publication. Raw tool logs preserve whitespace through scoped .gitattributes; source whitespace checks remain enabled.

Current resumable checkpoint: progress.md. G8 and release are blocked by upstream 108; these successful independent UDP checks do not waive it.


## Historical remote attempts (superseded by final results above)

Remote raw evidence: `p6-remote-wire.json`, `p6-remote-dhcp.log`, `p6-remote-regressions-initial.json`, `p6-remote-macos-initial.log`. Remote wire/package run https://github.com/gsmlg-dev/abyss/actions/runs/38395163332 tests committed sourcee120451. macOS initial3failures are fixture address provisioning, not an accepted portable result; all assertions remain in place.

Remote fixture rerun evidence: `p6-remote-regressions-fixture-rerun.json`, `p6-remote-macos-fixture-rerun.log`, https://github.com/gsmlg-dev/abyss/actions/runs/38396188342 (e79ffac). Linux OTP27/28 PASS, macOS192tests/1idle-test failure; owned alias cleanup PASS. Original40ms idle deadline, max_keys1 and all assertions retained.

Latest idle-test repair source (151-file manifest c30c3ba9289814f6c88a86332022f58b224bb106508c29cbe615be174410b2c7): `p6-idle-barriers-otp27.log`/OTP28 each21tests0failures; `p6-full-otp27-idle-final.log`/OTP28 each646tests+3doctests0failures, seed953627. `p6-idle-final-qa-otp27.log` formatPASS; `p6-credo-idle-final-comparison.log` baseline83/current84/new1 required upstreamTODO only. Round1 debug-hook badarity failure retained in `p6-idle-barriers-otp27-round1.log`; fixed with actual sys callback arity3. No production edit, deadline widening or timer mutation. Actual dc33e3e macOS run38398436753 passes idle test but fails blocked-writer normal-termination assertion within1000ms;192tests/1failure. Linux OTP27/28 and owned macOS fixture cleanup PASS. G9 remains FAIL pending investigation.

Remote idle repair rerun: https://github.com/gsmlg-dev/abyss/actions/runs/38398436753 (dc33e3e); `p6-remote-regressions-idle-rerun.json` and `p6-remote-macos-idle-rerun.log`. Idle test PASS; blocked writer expected normal worker termination missing. No production/source attribution claimed yet.

New production defect: controlled runtime tracing shows helper terminal result + actual normalDOWN followed by effects watchdog killing worker while only internal settlement remains. This invalidates G3/G7 until minimal source repair and deterministic red/green plus affected checks pass. Original macOS failure lacks full tracing, so attribution is limited to proved identical interleaving, not asserted remote scheduling.

Current effects-source checkpoint supersedes the historical failed interleaving above: minimal retirement fix and red/green tests are implemented, all current Linux QA/stress/performance pass. G3/G7 restored PASS on local declared environments; G9 remains FAIL until actual current-source macOS/remote matrix acceptance. Controlled diagnostics with invalid absolute coverage-export prefixes are attribution evidence only, not accepted coverage checks. G8/G10/release remain upstream108blocked.

Actual9c92636 remote results: network38401853225 all19jobs PASS (`p6-remote-network-effects.json`); local freshOTP27packaging PASS (`p6-p5-consumers-effects-otp27.log`), optional11actualDHCP/ARPgates. Regression38401847814 macOS and UbuntuOTP28 PASS, UbuntuOTP27 absolute-stop test FAIL (drain caller exits {:runtime_exit,:killed} at original20msdeadline). `p6-remote-regressions-effects-initial.json`, `p6-remote-effects-otp27-initial.log`, `p6-remote-macos-effects-pass.log`. G7/G9remainFAILuntil genuine stop repair and selected-source verification.

Stop-source remote38404701185 retained in `p6-remote-regressions-stop-initial.json`/`p6-remote-macos-stop-initial.log`: Linux27/28PASS, macOS newly added watchdog testFAIL; owned loopback setup/cleanup PASS. Current test-only harness repair explicitly orders real expired timer after actual effects-result/normalDOWN, rather than assuming completion within30ms. Original deadlines/payloads/quotas/assertions and production source unchanged. Full local checks and actual final macOS rerun pending. Final network38404707197 all19PASS and freshOTP27archive consumersPASS on4645a5ec.

Watchdog harness portable diagnostic reproduction and raw logs: `evidence/watchdog-harness-diagnostics.md`. Mutated/reloaded modules prove discrimination/order only and are explicitly invalid coverage evidence. Final real-source covered23/0eachruntime and101single-testrepetitionsPASS; mandatoryCredo still83baseline/84current/new1TODO. Application/wire/package/performance bytes unchanged from4645a5ec.
