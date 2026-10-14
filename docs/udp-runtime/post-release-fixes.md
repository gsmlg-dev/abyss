# Abyss post-release hardening

Work is in progress; no new release is claimed. Scope is Agent Note `27a599ba-c246-4263-92e9-77b80ef5605c` (revision 2), R1–R4, read in full. The immutable 0.8.0 release and [historical acceptance](../archive/udp-runtime/acceptance.md) remain attributed to their original sources.

Baseline `cd65c84073c66de460ab883206414cf8ce0154bf`; worktree `.trees/post-release-hardening`, branch `codex/post-release-hardening`. Primary had only three untracked user input Markdown files, preserved. Exact commands, exit codes and source/runtime hashes will accompany the discriminating regressions and final validation.

| Finding | Verification/result | Evidence |
|---|---|---|
| R1 stale cross-phase watchdog | PASS: isolated final-harness RED4tests/2 intended failures; fixed scoped46/0 each OTP27/28 | `evidence/post-release/r1-*` |
| R2 endpoint idle eviction | PASS: final RED 4 tests / 2 intended failures; fixed combined 50/0 each OTP27/28 | `evidence/post-release/r2-*` |
| R3 missing native send telemetry | PASS: final RED 15 tests / 5 intended failures; fixed combined 84/0 each OTP27/28 | `evidence/post-release/r3-*` |
| R4 public drop omission/overlap | PASS: portable RED 14/14 intended failures; native RED 2/2; stopped-window extension RED; final combined 144/0 OTP27/28, native 2/0 each | `evidence/post-release/r4-*` |

Reproduction inputs and raw evidence live in [post-release evidence](evidence/post-release/); resumable ownership and next steps are in [progress](progress.md).


Baseline checkpoint (2026-10-14): actual cd65c84 OTP27 strict compile and full integration suite PASS,648tests+3doctests/0failures, exit0 (`baseline-otp27-tests.log`). Strict Credo actualbaseline 83findings/exit30 (`baseline-credo.json`, raw log). No source edits or lock changes in primary. R1 actual timer race regressions underway; R3/R4 source findings confirmed by independent read-only audit.


Baseline resource gate PASS, exit0 (`baseline-runtime-stress-otp27.log`): all3policies ×5epochs, process baseline/final116, input high8items/7160bytes and egress4entries/2048bytes within configured quotas. These are sampled host-managed counters, not a whole-VM/native reclamation proof. Performance comparison will use actualcd65c84 source with controlled serial samples after compile/test activity finishes.


R1 checkpoint: final actual-timer cross-phase regressions fail oldcd65c84 independently (4tests/2 intended stale init/callback kills, isolated `.trees/r1-red-baseline`, exit2). Fixed source preserves active init/callback/effects and bounded cleanup; stale invocation/key/generation arms harmless. OTP27/28 each46tests/0, exit0. Source hashes/commands in `r1-source-identity.json`; raw final RED/green logs retained. Other timer classes audited, no demonstrated analogous identity reuse changed. R1 ownership returned; next R2 endpoint lifetime.

R2 checkpoint: isolated `babc1d1` fails final lifetime regressions (4 tests, 2 intended failures, exit 2). Fixed OTP27/28 each pass 50 interacting tests, exit 0. Endpoint state and its timer survive inactivity and pause/resume with zero completed input/egress credit; actual stop/replacement cancels old timers. Keyed eviction/status stability, obsolete-timer isolation and existing maximum-key limits remain tested. Production change is a three-line endpoint empty-queue guard. Commands/hashes in `r2-source-identity.json`. Next: R3 native local-send instrumentation and discriminating accounting regressions.

R3 checkpoint: isolated `d9c01b1` final-byte RED gives 15 tests / 5 intended failures, exit 2 (four native missing events after actual receive, one false GenUDP validation error). Fixed OTP27/28 each pass 84 interacting tests, exit 0. Actual IPv4/IPv6, all three backends, sampling 0/1, empty/strict sends, both transmitting same-handler endpoints, socket errors and delayed completion agree with receipts and counters. Portable failure uses a real 65,536-byte UDP send (`:emsgsize`); Linux native port-zero error is `:einval`. No Writer change. Commands/hashes in `r3-source-identity.json`. Credo retains 83 baseline findings plus two introduced R1 runtime nesting findings, which parent will fix before R4.

Watchdog lint checkpoint: R3 committed `c1aff38`; two introduced R1 nesting findings resolved using small expiry/phase helpers with unchanged arm identity, deadlines and cleanup barriers. OTP27/28 scoped interacting suites pass 79/0 (exit 0; exact command excludes the five unchanged endpoint-contract tests from R3's 84-test command). Strict Credo is absolute FAIL/exit 30 with exactly the same 83 baseline issue signatures; delta PASS, zero new or removed findings (`watchdog-lint-comparison.json`). Next: ordered R4 public drop accounting.

R4 acceptance: fixed-cardinality network counters count definitive ingress or runtime rejection once; rejected timer/outcome events have separate counters and telemetry. Real traffic covers key/item/byte/route/global/validation/pause limits, two endpoints, reset scope, native kernel truncation and sampling 0/1. Absolute runtime snapshots are sent before rejection telemetry, guarded by runtime PID/generation, and retained through normal or deadline-forced drain; no listener increment duplicates a runtime rejection. Native truncation reports observed bytes only. Final stopped-window regression fails the pre-extension candidate on lost runtime count. Commands, source hashes and all failed attempts are retained in `r4-*` evidence.

Patch preparation: GitHub/Hex latest version rechecked as 0.8.0; 0.8.1 selected. Combined final validation and publication remain pending. Absolute strict Credo is still FAIL with 83 baseline findings; acceptance requires zero introduced findings, with the normalized comparison retained.
