# Codex Fix Prompt — Abyss 0.8.0 Post-release Hardening

Repository: `gsmlg-dev/abyss`  
Reviewed release: `0.8.0`, commit `7d3a29f4206457669afa60a762a78eb7b90d2690`  
Reviewed evidence-only follow-up: `0d6531d087db262bf09c3caa363ea8c0644f4389`  
Scope: four focused fixes following the UDP runtime implementation, followed by validation, commit, push, and a new patch release using the repository's established release process. The user explicitly authorized this completion workflow on 2026-10-14.

## Mission and authority

Implement the four fixes below in the existing repository. Deliver working code, discriminating regressions, updated public contracts, and reproducible acceptance evidence. Do not stop at a plan or skeleton implementation.

Use the actual checkout. The SHAs above identify the review, not a revision to reset to. Read applicable `AGENTS.md`, current development instructions, `docs/udp-runtime/design.md`, `migration.md`, `acceptance.md`, and the relevant tests before editing. Record HEAD, dirty status, OS, Elixir/OTP/ERTS, and dependency identity. Preserve user changes, lockfiles unless a demonstrated need requires otherwise, and historical evidence.

Treat each finding as a review input to verify at actual HEAD. If already fixed, record the fixing source and demonstrate the regression rather than adding a second workaround. Distinguish confirmed behavior, controlled race reproduction, and untested environmental assumptions.

This is a maintenance pass, not another execution of the original P0–P6 architecture project. The explicit endpoint-lifetime decision below governs this change. Do not broaden it into new transports, protocols, queue systems, or a runtime rewrite.

## R1 — Isolate watchdog identity across execution phases

**Primary files:** `lib/abyss/datagram_runtime.ex`, related worker protocol, and `test/abyss/datagram_runtime_test.exs`.

### Review finding

At the reviewed source, initialization, callback execution, and effects execution reuse an expiry message shaped as `{:work_expired, key, input_token}`. A phase transition cancels the prior timer and stores a new timer reference, but expiry handling checks only the input token and whether the current watchdog is a reference.

Consequently, an old phase's already-generated expiry can match a new phase's active watchdog for the same input. The completed-effects fix that clears the watchdog does not by itself protect transitions while a replacement watchdog is active.

### Required implementation

- Give **every watchdog arm** its own identity, distinct from the input/invocation token. Store its phase and absolute monotonic deadline with that identity. Include sufficient identity in the expiry message to match the exact active arm.
- Accept expiry only when the current worker, invocation, phase, and watchdog identity match. Stale expiry is a no-op, even when another watchdog is active for the same input. Keep existing endpoint-generation isolation; do not reuse identities after restart.
- Treat cancellation as timer cleanup, not proof that a previously emitted message cannot arrive. Invalidate the old identity when advancing phases or retiring the watchdog.
- Preserve the actual init/callback/effects/cleanup limits, the single overall stop deadline, and externally enforced callback isolation. Do not fix the race by extending deadlines, disabling watchdogs, or treating all late expiry as harmless.
- Preserve the completed-effects terminal-result/helper-DOWN/worker-settlement protections already implemented. Receiving a result is not automatically permission to release protected input or in-flight egress credit. Do not remove those barriers to simplify this fix.
- Audit the other timer classes for the same identity-reuse pattern, but change only demonstrated analogous defects. Preserve managed-timer replacement tokens, idle tokens, receipt expiry, and generation checks.

Use small transition/validation helpers where useful. No broad GenServer rewrite.

### Required regressions

Test init → callback and callback → effects independently. Use a real UDP consumer and controlled barriers to make an **actual previous watchdog expiry** reach the runtime after it has installed the next phase's watchdog. Assert that the worker survives the stale expiry and that its current phase can complete.

Also prove that the new active watchdog still terminates genuinely blocked work, and that stale expiry cannot affect a later invocation, replacement keyed worker, or replacement endpoint generation. Retain the existing completed-effects and blocked-writer regressions.

Use real timers and observable phase/monitor barriers for the race tests. An additional direct transition test is useful but is not a substitute. Do not depend on narrow sleep-based timing luck. Test harness code may hold message delivery to establish the intended ordering; it must not fabricate an expired timer, remove the active timer, or claim an ordering it did not observe.

**Acceptance R1:** the old source fails the new cross-phase regression for the intended reason; corrected source ignores only stale arms and still enforces current deadlines. Credit/resource cleanup remains correct.

## R2 — Give endpoint state an endpoint lifetime, not a keyed idle lifetime

**Primary files:** `lib/abyss/datagram_runtime.ex`, `server_config.ex`, public handler documentation, and lifecycle tests.

### Review finding

At the reviewed source, an empty worker queue arms the same idle timer for both `:endpoint` and `:keyed`. Default idle expiry removes the worker and cancels its managed timers. Thus a live endpoint can silently reset application state after 60 seconds, and a timer scheduled beyond that idle interval can disappear without the socket generation changing.

### Required behavior decision

Implement this explicit policy:

| Execution policy | Lifetime |
|---|---|
| `:per_datagram` | One admitted invocation, bounded effects completion/receipt handoff, then cleanup. Unchanged. |
| `:endpoint` | Once initialized, one application state persists for the current endpoint generation. Ordinary idleness does not evict it. |
| `:keyed` | Preserve finite per-key idle eviction, maximum-key bounds, and current explicit stop/error behavior. |

- Do not arm a keyed idle-eviction timer for `:endpoint`. Retain lazy initialization if that is the current contract; this task does not require eager callbacks at startup.
- Keep `idle_timeout` as the keyed idle-eviction setting. Document that it does not govern `:endpoint` lifetime. Do not globally accept `:infinity` for runtime limits or weaken input, key, timer, callback, action, or writer bounds.
- Preserve endpoint state and its managed timers across inactivity and pause/resume within the same generation. Pause remains an admission barrier, not a promise to freeze all already-admitted application work or timer time.
- Endpoint stop, generation replacement, an explicit application stop/error, or a genuine callback failure may still retire state under the existing failure policy. Document these exceptions: persistence is neither durable storage nor recovery of state from a failed callback.
- For `:keyed`, keep existing idle eviction and cancellation of that key's managed timers. Explicitly document that pending timers do not implicitly pin an otherwise idle key in this patch. Do not make keyed workers immortal or automatically recreate an evicted key when an obsolete timer arrives.
- Preserve bounded termination hooks and remove all managed timers on their actual owning worker/generation teardown. Idle endpoint workers must hold no completed input reservations or finished-send credit merely to retain application state.

No additional optional endpoint-eviction feature is needed in this maintenance pass.

### Required regressions

Use a short configured keyed idle interval rather than waiting a minute. Process one datagram under `:endpoint`, wait past that interval, then process another: assert the same worker and generation, exactly one initialization, and the expected accumulated state. Use the public consumer for the behavioral assertion.

Schedule an endpoint managed timer with a delay greater than that interval and verify it fires once, preserving state. Verify pause/resume does not reset state; stop and generation replacement cancel old timers and cannot deliver events to new state.

Separately prove `:keyed` still expires inactive keys, cancels their timers according to the documented policy, bounds key count, and does not refresh idle lifetime on status calls. Keep per-datagram and legacy handler behavior unchanged.

**Acceptance R2:** endpoint state/timers survive ordinary idleness with no artificial input retention; keyed eviction and failure/shutdown cleanup remain bounded and tested. Migration notes call out the corrected lifetime.

## R3 — Instrument actual native send outcomes exactly once

**Primary files:** `lib/abyss/transport/udp/native.ex`, `transport/udp/core.ex`, `datagram_dispatcher.ex` Writer, and `telemetry.ex`.

### Review finding

The GenUDP transport records actual send outcomes through `Core.record_send/3` and `Telemetry.track_send_result/4`. The reviewed native path calls `:socket.sendmsg` without the equivalent instrumentation, while Writer provides receipts but does not fill that gap.

### Required implementation

- Ensure supported native ordinary sends and strict replies record the same local-outcome counters/events as their GenUDP counterparts, under the correct registered logical server scope.
- A successful completed local socket send increments `responses_total` once and adds the actual payload length to `bytes_sent`. A zero-length UDP datagram counts as one successful send and zero payload bytes.
- A definite failed socket-send attempt increments `send_errors_total` once, with no successful-send or successful-byte increment. Preserve the transport result and error reason.
- Emit the existing `[:abyss, :datagram, :send]` event once per recorded local send result with the documented metadata and payload-byte measurement. Do not count serialized addressing controls as payload bytes; egress admission accounting may continue to include them.
- Pick one instrumentation boundary per send path. Prefer a minimal native equivalent of the established transport hook unless a small shared helper is demonstrably safer. Do not add unconditional Writer counting on top of GenUDP's existing hook.
- Do not count admission, `await`, receipt inspection, a caller's wait timeout, or repeated receipt reads as another network send. Waiting timeout is not a socket-send failure. If an accepted send completes later, count its actual completion once.
- Validation/admission rejections that never attempt a socket send must not masquerade as socket-send errors or successes. Keep these distinct from transport failures. Do not fabricate completion for forced teardown with an unknown outcome.
- Keep telemetry independent of connection-span sampling. Preserve custom-transport and optional QUIC/legacy Writer contracts; do not assume an uninstrumented custom transport has new guarantees.

### Required regressions

Exercise GenUDP inet, GenUDP socket, and Linux native through supported public APIs. Cover native IPv4/IPv6 ordinary sending and strict replies, empty payloads, definite local send failures, and two endpoints using the same handler with isolated metrics.

Use real socket send/receive for success evidence. Use a controlled actual socket error for the local-failure case and a fake/blocking transport only for deterministic receipt/race tests. Test a rejected strict reply without metadata and queue rejection: neither is an actual socket send.

Verify deltas and event counts at sampling rates 0 and 1. Prove GenUDP did not become double-counted and that an accepted send completing after caller timeout is counted only once.

**Acceptance R3:** native receipts and transport telemetry agree on actual local outcomes; other paths retain their counts and return contracts. No peer-delivery claim is introduced.

## R4 — Make public drop statistics complete and non-overlapping

**Primary files:** `lib/abyss/listener.ex` endpoint info/admission paths, `datagram_runtime.ex`, `endpoint.ex`, and telemetry/accounting tests.

### Review finding

The reviewed endpoint-info merge overwrites runtime `dropped` with the listener's identically named field. Deferred routing/key/queue rejection after initial admission is therefore absent from the public total. Conversely, synchronous admission rejection may already increment both internal counters, so simply summing them would double-count.

Runtime timer/outcome events also pass through input admission; their rejection must not be reported as loss of an additional network datagram.

### Required public semantics

- For the new API, `Endpoint.info/1` and `Endpoint.status/1` must report all **known current-generation network datagram drops**, consistent with the lifetime of the existing `received` field. Preserve legacy statistics contracts and document scope/reset behavior explicitly.
- Count each network input at most once at the stage that definitively rejects it: ingress validation/pause, runtime input admission, or deferred routing/key/queue rejection. Do not count a successfully admitted packet as dropped merely because a status snapshot precedes its completion.
- Expose a small, documented, non-overlapping breakdown where useful. A viable model separates ingress drops from runtime network-input drops and separately tracks internal-event rejection. Storage may reuse the existing counter infrastructure; there must be one authoritative accounting decision for each rejection, not duplicate independently incremented totals.
- Keep bounded cardinality. Do not create permanent metric keys from source addresses, arbitrary route keys, payloads, or exception values. Dynamic detail belongs in event metadata, not an unbounded counter namespace.
- Track rejected timer and send-outcome events separately. Do not inflate `datagrams_dropped` for them. Likewise distinguish callback failure, transport-send failure, and intentionally discarded queued work during teardown; document which concrete network-input rejection events enter the drop total.
- Public status and telemetry must agree for the same scope and observed interval. Telemetry may retain its documented logical-server lifetime across generations; do not compare it blindly with a current-generation snapshot or silently change historical reset semantics.
- Preserve admission release-once invariants, drop-new policy, and endpoint isolation. Do not require another synchronous listener→runtime→listener cycle or introduce a control-path deadlock to synchronize counters.

### Required regressions

Drive real datagrams and assert totals using **public Endpoint info/status**, not only private runtime inspection. Cover over-limit keys, per-key item and byte limits, over-large route keys, a blocked/failed route, global admission rejection, ingress packet-size/required-metadata rejection, and pause rejection.

Prove a synchronous admission rejection appears once, a deferred rejection remains visible, and internal timer/outcome rejection affects only the corresponding internal-event statistic. Exercise two endpoints, repeated status reads, and restart/reset scope behavior.

Use readiness and completion/rejection barriers so assertions occur after the relevant decision. Do not treat an arbitrary delay or receipt of an unrelated message as proof that a deferred route rejection has completed. Existing tests that inspect runtime internals can remain diagnostic, but the public contract needs its own assertions.

**Acceptance R4:** public totals include every tested rejection path exactly once, categories reconcile without double-counting, and internal events are not mislabeled as network loss. Unknown kernel receive-queue loss is not invented or included.

## Compatibility and scope guardrails

Preserve legacy `Abyss.Handler` tuple input, returned state and cleanup, raw-socket behavior on compatible backends, and legacy broadcast one-shot semantics. Do not change the meaning of legacy `{:continue, state}`.

Retain wrong-peer client filtering and its absolute deadline, effective GenUDP driver resolution, multicast membership identity/rollback/restoration, native destination/interface/scope truthfulness, and strict original-socket reply behavior. Broadcast/multicast still use one receiver; no new socket pooling or deduplication.

Keep input/action/timer/writer limits finite. Preserve admitted versus completed versus unknown receipts, caller-death behavior, generation invalidation, forced cleanup, and the absolute stop deadline. No automatic callback replay, datagram retransmission, or timeout-as-cancellation shortcut.

Keep core UDP independent of Rust/DHCP-native/QUIC dependencies and retain the explicit optional DHCP migration. Do not alter QUIC engine state ownership, stream contracts, application-session draining, or sibling projects. No TCP/TLS/Phoenix/Gaoxy/protocol-parser work.

Do not reset the checkout, remove user files, delete failing tests, weaken assertions/coverage thresholds, silently suppress lint, change the supported runtime claim, or increase production timeouts to obtain green tests.

Local code, test, and documentation changes, an appropriate patch version/changelog update, commit, push, and release are authorized for this task. After required validation passes, complete the repository's established delivery workflow without requesting another routine confirmation. Commit only task-owned changes and preserve unrelated user work. Respect branch protection and required CI/approvals; do not force-push, overwrite published tags/releases, expose secrets, or publish unrelated packages. Use the actual latest version and repository conventions to choose the next patch release rather than assuming 0.8.1 is still available. The extracted optional DHCP package remains outside this publication scope.

Do not stop at local modifications after successful validation: create the commit, push the appropriate branch, follow the established integration/release workflow, and verify the new tag, GitHub release, and Hex publication where applicable. If required checks, permissions, credentials, branch approvals, or publication fail, report the exact blocker and actual completed steps; do not claim release success or bypass the failed gate.

## Execution, evidence, and completion

Work in order R1 → R2 → R3 → R4. Establish a focused failing regression before each fix; keep related changes reviewable. Run interacting lifecycle/accounting tests after each step, then final integration tests on the combined source.

Use the existing devenv/Nix setup and inspect current Mix aliases/scripts. Starting commands, adapted only to the actual checkout layout:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
MIX_ENV=test mix compile --warnings-as-errors
mix test --include integration --no-cover
mix dialyzer
mix credo --strict
git diff --check
```

Run focused regressions on Linux OTP 27 and 28; native-wire tests require Linux. Run the portable macOS subset where a runner is available. Reuse the existing UDP network fixtures for the affected backend/policy matrix and independent-peer strict replies. Run existing dispatcher/Writer tests and unchanged optional QUIC consumers after shared changes. Verify a clean core package consumer still builds/runs without Rust or QUIC; retain optional-package compatibility checks where affected.

Observe privileges and fixture requirements. Use only fixture-owned namespaces/interfaces, never the ambient LAN or host routing configuration. An unavailable runtime, privilege, or peer is a named BLOCKED/NOT RUN gate, not a passing mock substitute. Existing green CI is historical evidence, not evidence for these changes.

Compare strict lint and relevant resource/performance checks against actual HEAD before editing. The earlier review described existing lint and performance limitations; do not assume the same counts remain current or claim to fix them without measurement. Fix introduced findings without unrelated mass refactoring.

Create `docs/udp-runtime/post-release-fixes.md` with R1–R4 results, exact source/worktree identity, commands, exit codes, and evidence paths. Append a dated checkpoint to `progress.md`; update design/migration/telemetry documentation for the corrected contracts. Link from acceptance documentation without replacing or relabeling 0.8.0's historical test results.

The final report must give R1–R4 PASS/FAIL/BLOCKED/NOT RUN, the specific regressions and observed outcomes, compatibility changes, final runtime/backend coverage, pre-existing versus introduced failures, and any remaining concrete blocker. Include the tested commit SHA, pushed branch, release version/tag, relevant CI results, and verified publication links/status. If any work remains uncommitted or unpublished, identify it precisely and explain the blocker. Do not declare completion merely because the original suite is still green or a release command was submitted.

## Review source anchors

These identify the source used in the review; verify against actual HEAD before changing it.

- Runtime/phase/lifetime/effects: `lib/abyss/datagram_runtime.ex` at `7d3a29f4206457669afa60a762a78eb7b90d2690`.
- Public info and listener admission: `lib/abyss/listener.ex` and `lib/abyss/endpoint.ex` at the same commit.
- Actual send and accounting: `lib/abyss/transport/udp/native.ex`, `transport/udp/core.ex`, `datagram_dispatcher.ex`, and `telemetry.ex` at the same commit.
- Existing limits and regressions: `lib/abyss/server_config.ex`, `test/abyss/datagram_runtime_test.exs`, and the current UDP fixtures.
- Public contracts: `docs/udp-runtime/design.md` and `migration.md` at the same commit.

The review was source-based; new race and behavior tests must establish their own evidence. This prompt does not claim that the four new regressions have already been executed.

