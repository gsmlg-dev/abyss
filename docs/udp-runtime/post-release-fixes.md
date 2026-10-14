# Abyss post-release hardening

Work is in progress; no new release is claimed. Scope is Agent Note `27a599ba-c246-4263-92e9-77b80ef5605c` (revision 2), R1–R4, read in full. The immutable 0.8.0 release and [historical acceptance](../archive/udp-runtime/acceptance.md) remain attributed to their original sources.

Baseline `cd65c84073c66de460ab883206414cf8ce0154bf`; worktree `.trees/post-release-hardening`, branch `codex/post-release-hardening`. Primary had only three untracked user input Markdown files, preserved. Exact commands, exit codes and source/runtime hashes will accompany the discriminating regressions and final validation.

| Finding | Verification/result | Evidence |
|---|---|---|
| R1 stale cross-phase watchdog | PASS: isolated final-harness RED4tests/2 intended failures; fixed scoped46/0 each OTP27/28 | `evidence/post-release/r1-*` |
| R2 endpoint idle eviction | NOT RUN | Pending |
| R3 missing native send telemetry | NOT RUN | Pending |
| R4 public drop omission/overlap | NOT RUN | Pending |

Reproduction inputs and raw evidence live in [post-release evidence](evidence/post-release/); resumable ownership and next steps are in [progress](progress.md).


Baseline checkpoint (2026-10-14): actual cd65c84 OTP27 strict compile and full integration suite PASS,648tests+3doctests/0failures, exit0 (`baseline-otp27-tests.log`). Strict Credo actualbaseline 83findings/exit30 (`baseline-credo.json`, raw log). No source edits or lock changes in primary. R1 actual timer race regressions underway; R3/R4 source findings confirmed by independent read-only audit.


Baseline resource gate PASS, exit0 (`baseline-runtime-stress-otp27.log`): all3policies ×5epochs, process baseline/final116, input high8items/7160bytes and egress4entries/2048bytes within configured quotas. These are sampled host-managed counters, not a whole-VM/native reclamation proof. Performance comparison will use actualcd65c84 source with controlled serial samples after compile/test activity finishes.


R1 checkpoint: final actual-timer cross-phase regressions fail oldcd65c84 independently (4tests/2 intended stale init/callback kills, isolated `.trees/r1-red-baseline`, exit2). Fixed source preserves active init/callback/effects and bounded cleanup; stale invocation/key/generation arms harmless. OTP27/28 each46tests/0, exit0. Source hashes/commands in `r1-source-identity.json`; raw final RED/green logs retained. Other timer classes audited, no demonstrated analogous identity reuse changed. R1 ownership returned; next R2 endpoint lifetime.
