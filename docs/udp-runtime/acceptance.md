# UDP runtime acceptance

P0–P6 implementation and acceptance are complete on the tested 0.8.0 source. Final local QA, unchanged optional QUIC consumers, Linux/macOS regressions and19-job network/package matrix PASS. Publication verification is next.

## Source and environment

Baseline: `9b710e6480900e16e304f40e63623aff8c922e19`, version 0.7.0. Candidate: `codex/udp-runtime`, version 0.8.0, in `.trees/udp-runtime`. The user authorized implementation, commits, push and next minor release. Original user documents are preserved and excluded from commits; sibling repositories and ambient LAN settings are untouched.

The tested151-file implementation manifest is `4acbce68f6f111da1f1a47c7c78273ecbcbec8cea86096179380c62e1b423e89`; final documentation-updated manifest is `4acbce68f6f111da1f1a47c7c78273ecbcbec8cea86096179380c62e1b423e89` (`evidence/final-source-sha256.log`). `final-source-identity.json` records source commits and runtime identity. Linux tests use devenv Elixir1.18.4/OTP27/ERTS15.2.7.4 and system Elixir1.18.5/OTP28/ERTS16.4.0.5 with isolated builds. The declared Elixir `~>1.13` minimum is unchanged and explicitly unverified; native UDP's Linux/OTP27 minimum is tested. macOS supports the portable subset only.

## G0–G10

Evidence paths below are relative to [evidence/](evidence/). Historical checkpoints are identified separately; they do not substitute for a pending final remote result.

| Gate | Status | Evidence and limits |
|---|---|---|
| G0 Baseline | PASS | `baseline-runtime.log`, `baseline-tests.log`:573 tests+3 doctests/0 failures; `baseline-credo.json`:83 existing findings/exit30. Progress records F1–F6 applicability and legacy API inventory. |
| G1 Correctness | PASS | Discriminating peer/backend/idempotence RED logs and `p1-green-otp27.log`:226 scoped tests; five fresh BEAM backend resolutions per OTP27/28. Final full tests preserve wrong-peer and absolute-deadline assertions. |
| G2 Public contracts | PASS | `p2-contracts.log`, real GenUDP examples and final full suites:Datagram/Handler/Endpoint consumers, unchanged legacy/custom handler behavior, empty packets and telemetry-independent metadata. |
| G3 Execution/effects | PASS | Three public policies, explicit route ordering, bounded inputs/actions/receipts, protected helper/worker DOWN accounting, callback watchdogs and no replay. `p3-retained-work-tests.log`, final full suites and actual three-policy stress in `p6-release-candidate-otp27-qa.log`. |
| G4 Receive metadata | PASS | Final source9ecd90cae1e630478a41c54e2ca0c882750a045a network38507074883:18 OTP27/28×backend×policy runs, native21 independent-peer gates each; actual IPv4/IPv6 destinations, interface indices/scopes and truncation tests. `p6-final-remote-wire-evidence.json` and19 raw logs. |
| G5 Egress | PASS | Same actual-wire matrix:original socket/source/interface/port and two link-local scopes. Inet15 gates; socket10 explicitly supported-subset gates with scoped IPv6 unavailable. Strict requirements reject rather than fall back. |
| G6 Packaging | PASS | OTP27/28 archive-content core consumers without Rust/native/QUIC and explicitly installed optional NIF consumers,11 actual DHCP/ARP gates (`p5-final-consumers-otp27.log`, OTP28 counterpart). Fresh0.8 candidate archive verification PASS/exit0 (`p6-release-candidate-package-otp27.log`), including core no-Rust/no-QUIC and optional11 actual DHCP/ARP gates. Optional DHCP package remains unpublished. |
| G7 Lifecycle/resources | PASS | Final OTP27/28 full648+3/0; covered runtime23/0 each and TableOwner1/0 each. Actual input/egress quotas, worker/helper/component DOWN, pause/resume/membership, generations, idle/callback/stop deadlines and five stress epochs per policy. No whole-VM or native reclamation claim from snapshots. |
| G8 Existing consumers | PASS | Fixed published elixir_quic/ex_ssl0.21.6 exact pins and Hex checksums. `p6-quic-0216-check-final.log` and `p6-quic-0216-independent-final.log`, exit0:unchanged concurrent echoes/collector, Retry/control/lifecycle, fresh outside consumers, actual release echo/collector and UDP without QUIC. Upstream108 is closed; no local workaround. |
| G9 Runtime/backend matrix | PASS | Exact source9ecd90c: regression38507071297 attempt2 all3 jobs PASS (Linux OTP27/28, macOS OTP28); network38507074883 all19jobs PASS. Attempt1 macOS unchanged legacy idle-expiry notification arrived at300ms boundary; retained separately. No test/code change on retry. Owned macOS loopback setup/cleanup PASS. Minimum Elixir explicitly unverified; no macOS native claim. |
| G10 QA/handoff | PASS | Final OTP27/28 each648 tests+3 doctests/0 failures; format, dev/test warnings-as-errors compile, Dialyzer0 errors/0 skips, examples and native strict replies PASS. Strict Credo baseline83/current83/new0; absolute lint remains FAIL/exit30 on pre-existing findings. No suppression. Design/migration/P5 notes/performance/diagnostic generators and progress are included. |

## Final local verification

- `p6-release-candidate-otp27-qa.log`:format/dev+test compile/full tests/Dialyzer/examples/native IPv4/IPv6 replies/three-policy stress/diff checks, exit0.
- `p6-release-candidate-otp28-full.log`:648 tests+3 doctests,0 failures, exit0, seed953627.
- `p6-release-candidate-credo-raw.log`, JSON and comparison:exit30,83 existing findings,0 new findings. The upstream TODO was removed after the fixed dependency passed the original workload.
- Source hashes were checked after QA. Controlled measurements on the same UDP runtime code report a 6.9% legacy throughput regression; [performance](performance.md) records source identity, commands and limits.

## Reproduce

From the primary checkout, OTP27 commands use:

```sh
devenv shell -- bash -c 'cd .trees/udp-runtime; <command>'
```

From the candidate worktree, OTP28 uses `ERL_FLAGS='+S 8:8' MIX_BUILD_PATH=/tmp/abyss-p6-otp28-final <command>`. Do not reuse stale OTP build paths or user-owned PLTs.

```sh
mix format --check-formatted
mix compile --warnings-as-errors
MIX_ENV=test mix compile --warnings-as-errors
mix test --include integration --no-cover --seed 953627
mix dialyzer
mix credo --strict --format json
git diff --check
sha256sum -c docs/udp-runtime/evidence/final-source-sha256.log
bash scripts/udp/backend_boot.sh
mix run example/datagram_echo.exs
mix run scripts/udp/runtime_smoke.exs
mix run scripts/udp/runtime_stress.exs
python3 scripts/udp/p5_consumers.py
bash scripts/phase1/check.sh
bash scripts/phase1/independent_check.sh
```

Wire fixtures require Linux `ip`, `setpriv`, and passwordless sudo; they create and remove their own namespaces and interfaces. Exit77 is BLOCKED, not PASS. Independent peers read actual interface indices. Repeat this command for each `inet|socket|native`, `per_datagram|endpoint|keyed`, and OTP27/28:

```sh
ABYSS_UDP_BACKEND=native ABYSS_UDP_API=datagram ABYSS_UDP_EXECUTION=keyed python3 scripts/udp/network_fixture.py
```

## Diagnosis and fixture fidelity

Failed attempts remain raw evidence. `watchdog-harness-diagnostics.md`, `writer-death-diagnostics.md`, `table-owner-scope-diagnostics.md` and the completed-effects fixture notes include portable reproductions and their limits. Mutated/reloaded runtime diagnostics are not coverage acceptance. Actual macOS observer records demonstrate completed effects retiring correctly; the observer is removed from final source.

Tests that require normally completed effects now establish that premise with genuine result/monitor DOWN and the original actual timer message. Separate unfinished-work deadline tests are unchanged. TableOwner tests acknowledge the real target DOWN handler before retaining the original100 probes/assertions. Expected Dispatcher crash logs are captured; its100ms assertion/body are unchanged. No production deadline or assertion was weakened.

## Resolved upstream issue

The baseline,0.21.4 and0.21.5 concurrent QUIC failures and direct `:ack_range_limit` reproducer are retained. PR110 (`31ddfd92193477ae182e9d6c7fa4508dcc4b659f`) fixed bounded receive history; issue108 closed,0.21.6 published and both optional consumers updated. Hex metadata, exact checksum provenance and the original unchanged workload passed. See `p6-upstream108-resolved.json`, `p6-upstream110-merged.json`,0.21.6 dependency/Hex records and the two final consumer logs.

## Remote and publication

Final remote source: `9ecd90cae1e630478a41c54e2ca0c882750a045a`. Regression [38507071297](https://github.com/gsmlg-dev/abyss/actions/runs/38507071297), attempt2, all3jobs PASS. Network/package [38507074883](https://github.com/gsmlg-dev/abyss/actions/runs/38507074883), all19jobs PASS. Raw logs, parsed wire gates, complete API metadata and both regression attempts are retained under `p6-final-remote-*`. Final release preparation changes only documentation/evidence; executable/test/workflow sources remain identical to the accepted candidate.

The extra local same-seed legacy diagnosis ran7tests/0failures, but its scoped6.73% coverage exits3 below the unchanged40% whole-project threshold (`p6-legacy-idle-same-seed-otp28.log`); it is diagnostic evidence, not coverage acceptance. Mandatory remote coverage gates passed.

Release/tag/Hex and fresh published-only verification remain pending. Exact next action is in [progress](progress.md). Earlier drafts and failed attempts remain with historical attribution.
