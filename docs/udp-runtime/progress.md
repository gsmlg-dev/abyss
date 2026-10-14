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
| R3 native local-send telemetry | NOT RUN |
| R4 public network-drop accounting | NOT RUN |
| Combined local/remote/package/QUIC validation | NOT RUN |
| Commit/push/patch release/published verification | NOT RUN |

Exact next action: finish R1 real-timer cross-phase RED/repair/green; record actual baseline results. Implement remaining fixes in order. Preserve [historical 0.8.0 progress](../archive/udp-runtime/progress.md) and acceptance as historical evidence.


Baseline checkpoint (2026-10-14): actual cd65c84 OTP27 strict compile and full integration suite PASS,648tests+3doctests/0failures, exit0 (`baseline-otp27-tests.log`). Strict Credo actualbaseline 83findings/exit30 (`baseline-credo.json`, raw log). No source edits or lock changes in primary. R1 actual timer race regressions underway; R3/R4 source findings confirmed by independent read-only audit.


Baseline resource gate PASS, exit0 (`baseline-runtime-stress-otp27.log`): all3policies ×5epochs, process baseline/final116, input high8items/7160bytes and egress4entries/2048bytes within configured quotas. These are sampled host-managed counters, not a whole-VM/native reclamation proof. Performance comparison will use actualcd65c84 source with controlled serial samples after compile/test activity finishes.


R1 checkpoint: final actual-timer cross-phase regressions fail oldcd65c84 independently (4tests/2 intended stale init/callback kills, isolated `.trees/r1-red-baseline`, exit2). Fixed source preserves active init/callback/effects and bounded cleanup; stale invocation/key/generation arms harmless. OTP27/28 each46tests/0, exit0. Source hashes/commands in `r1-source-identity.json`; raw final RED/green logs retained. Other timer classes audited, no demonstrated analogous identity reuse changed. R1 ownership returned; next R2 endpoint lifetime.

2026-10-14 R1 delivery checkpoint: committed `babc1d1`. Baseline steady samples completed serially for legacy/per_datagram/endpoint/keyed (three each), logs retained. R2 implementation owner hardening_r1; parent owns docs, integration and release. Publication verifier owns workflow regression path updates only. Exact next action: accept R2 discriminating RED/green, commit R2, then assign ordered R3.

R2 checkpoint: isolated `babc1d1` fails final lifetime regressions (4 tests, 2 intended failures, exit 2). Fixed OTP27/28 each pass 50 interacting tests, exit 0. Endpoint state and its timer survive inactivity and pause/resume with zero completed input/egress credit; actual stop/replacement cancels old timers. Keyed eviction/status stability, obsolete-timer isolation and existing maximum-key limits remain tested. Production change is a three-line endpoint empty-queue guard. Commands/hashes in `r2-source-identity.json`. Next: R3 native local-send instrumentation and discriminating accounting regressions.
