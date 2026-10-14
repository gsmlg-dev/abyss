# Post-release hardening progress

## 2026-10-14 — initial checkpoint

Read Agent Note `27a599ba-c246-4263-92e9-77b80ef5605c`, revision 2, in full. Its archived input is [agent-note](evidence/post-release/agent-note.md). Execute R1 → R2 → R3 → R4, then validate, commit, push and release the next available patch. User authorization includes this delivery workflow.

- Baseline/main: `cd65c84073c66de460ab883206414cf8ce0154bf`; preserve its documentation reorganization.
- Execution: `.trees/post-release-hardening`, branch `codex/post-release-hardening`.
- Original primary dirt: three untracked user `abyss-udp-*` Markdown files; no tracked changes.
- Current release is 0.8.0; verify patch availability again before publication.
- OTP27 uses the primary devenv shell; OTP28 uses the system runtime. Separate build paths prevent cross-runtime artifacts.
- Baseline OTP27 full integration/strict compile running against untouched primary source. Baseline lint and performance measurement pending.
- R1 agent owns runtime/worker/watchdog tests and R1 evidence. Accounting agent performs read-only R3/R4 audit. Root owns baseline, documentation, integration and delivery. Do not overlap these ownership boundaries.

| Step | Status |
|---|---|
| R1 watchdog arm identity | PASS — final RED and both runtimes green |
| R2 endpoint generation lifetime | PASS — real UDP lifetime and timer regressions |
| R3 native local-send telemetry | PASS — 15 accounting regressions and interacting suites |
| R4 public network-drop accounting | PASS — portable/native RED and final green, drain snapshot extension |
| Combined local/remote/package/QUIC validation | NOT RUN |
| Commit/push/patch release/published verification | NOT RUN |

Exact next action: finish R1 real-timer cross-phase RED/repair/green; record actual baseline results. Implement remaining fixes in order. Preserve [historical 0.8.0 progress](../archive/udp-runtime/progress.md) and acceptance as historical evidence.


Baseline checkpoint (2026-10-14): actual cd65c84 OTP27 strict compile and full integration suite PASS,648tests+3doctests/0failures, exit0 (`baseline-otp27-tests.log`). Strict Credo actualbaseline 83findings/exit30 (`baseline-credo.json`, raw log). No source edits or lock changes in primary. R1 actual timer race regressions underway; R3/R4 source findings confirmed by independent read-only audit.


Baseline resource gate PASS, exit0 (`baseline-runtime-stress-otp27.log`): all3policies ×5epochs, process baseline/final116, input high8items/7160bytes and egress4entries/2048bytes within configured quotas. These are sampled host-managed counters, not a whole-VM/native reclamation proof. Performance comparison will use actualcd65c84 source with controlled serial samples after compile/test activity finishes.


R1 checkpoint: final actual-timer cross-phase regressions fail oldcd65c84 independently (4tests/2 intended stale init/callback kills, isolated `.trees/r1-red-baseline`, exit2). Fixed source preserves active init/callback/effects and bounded cleanup; stale invocation/key/generation arms harmless. OTP27/28 each46tests/0, exit0. Source hashes/commands in `r1-source-identity.json`; raw final RED/green logs retained. Other timer classes audited, no demonstrated analogous identity reuse changed. R1 ownership returned; next R2 endpoint lifetime.

2026-10-14 R1 delivery checkpoint: committed `babc1d1`. Baseline steady samples completed serially for legacy/per_datagram/endpoint/keyed (three each), logs retained. R2 implementation owner hardening_r1; parent owns docs, integration and release. Publication verifier owns workflow regression path updates only. Exact next action: accept R2 discriminating RED/green, commit R2, then assign ordered R3.

R2 checkpoint: isolated `babc1d1` fails final lifetime regressions (4 tests, 2 intended failures, exit 2). Fixed OTP27/28 each pass 50 interacting tests, exit 0. Endpoint state and its timer survive inactivity and pause/resume with zero completed input/egress credit; actual stop/replacement cancels old timers. Keyed eviction/status stability, obsolete-timer isolation and existing maximum-key limits remain tested. Production change is a three-line endpoint empty-queue guard. Commands/hashes in `r2-source-identity.json`. Next: R3 native local-send instrumentation and discriminating accounting regressions.

R3 checkpoint: isolated `d9c01b1` final-byte RED gives 15 tests / 5 intended failures, exit 2 (four native missing events after actual receive, one false GenUDP validation error). Fixed OTP27/28 each pass 84 interacting tests, exit 0. Actual IPv4/IPv6, all three backends, sampling 0/1, empty/strict sends, both transmitting same-handler endpoints, socket errors and delayed completion agree with receipts and counters. Portable failure uses a real 65,536-byte UDP send (`:emsgsize`); Linux native port-zero error is `:einval`. No Writer change. Commands/hashes in `r3-source-identity.json`. Credo retains 83 baseline findings plus two introduced R1 runtime nesting findings, which parent will fix before R4.

Watchdog lint checkpoint: R3 committed `c1aff38`; two introduced R1 nesting findings resolved using small expiry/phase helpers with unchanged arm identity, deadlines and cleanup barriers. OTP27/28 scoped interacting suites pass 79/0 (exit 0; exact command excludes the five unchanged endpoint-contract tests from R3's 84-test command). Strict Credo is absolute FAIL/exit 30 with exactly the same 83 baseline issue signatures; delta PASS, zero new or removed findings (`watchdog-lint-comparison.json`). Next: ordered R4 public drop accounting.

R4 active checkpoint: baseline/HEAD `960c40a`. Accounting worker owns listener/runtime/telemetry code, portable public-drop regressions and evidence. Parent owns Endpoint public docs, migration/design/operations and delivery. Field contract agreed: `drop_counts` ingress/runtime network only; `internal_events_rejected` timer/send_outcomes. Preserve logical telemetry lifetime vs current-generation public scope. Exact next action: establish R4 public-contract RED, implement minimal accounting fix, accept interacting OTP27/28 green and zero-new lint, then combined integration/resource/performance/remote/package/QUIC gates before patch release.

R4 review checkpoint: initial portable RED 14/14 and current candidate scoped green 143/0 on both OTP27/28; separate genuine native truncation RED 2/2, green 2/0 each. Before acceptance, discovered and reproduced same-generation stopped-window omission: draining leaves public `received=1` but loses runtime drop total (1 -> 0). Root confirmed this violates requested counter lifetime and authorized minimal guarded absolute snapshots to retain network/internal counters after graceful or forced drain; no independent listener increments or synchronous control cycle. Accounting agent owns this extension and regression; native agent owns AliasUsage cleanup/final-byte RED/green refresh. Exact next action: accept extended R4 green and baseline-only Credo, update report, commit, then run prepared `/tmp/abyss-post-hardening-final.py` serially on combined versioned source. Release and remote checks remain NOT RUN.

2026-10-14 resumed checkpoint: final R4 production source stable; native final-byte tests pass OTP27/28, 2/0 each, and no new AliasUsage finding. Guarded snapshots reviewed: absolute bounded map, owning PID/generation, sender ordering before telemetry, retained after runtime retirement. Version/README/changelog prepared for available patch 0.8.1. Root owns final report/integration/release; accounting owner finishing OTP27 combined144/lint/source identity, native owner running unchanged optional QUIC checks. Exact next action: commit R4 and versioned candidate, run `/tmp/abyss-post-hardening-final.py` OTP27 then OTP28; resource/performance checks must run serially after all other jobs finish. Nothing pushed/published yet.
