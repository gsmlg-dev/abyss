# Published QUIC engine acceptance — internal request #5

Date: 2026-09-29. Scope: Abyss only, on the existing `main` branch.
Issue: [gsmlg-dev/abyss#5](https://github.com/gsmlg-dev/abyss/issues/5).
Release target: `0.6.1`. The tag and commit containing this report provide the
immutable Abyss source for downstream consumer fixtures. The original Phase 1
report and evidence remain historical snapshots of the Git engine acceptance.

## Reproduction and fix

Baseline Abyss commit: `50e121fce66daeb9cb25a2f5dc93050ca37efc5d`.
An isolated consumer with Hex `elixir_quic` 0.2.2 and `ex_ssl` 0.7.2 compiled,
then failed to start its supervised Abyss listener with
`:quic_backend_unavailable`. This failure was captured before runtime changes.

The published engine exports `Quic` and `Quic.Endpoint`, with OTP application
`:elixir_quic`; the old Git engine exported `QUIC`. Abyss now selects `Quic`,
delegates public operations to it and performs TLS credential preflight for that
backend. `SSL.QUIC` remains the correct TLS namespace. Endpoint ingress resolves
from the selected backend, so it uses `Quic.Endpoint` without a second API path.
There is no legacy alias or fallback. `Abyss.QUIC` and its handler interface remain
unchanged, and the optional engine is not added to the root runtime dependencies.

The independent echo and collection applications now pin Hex dependencies.
Their disposable test credentials are owned by the Abyss test harness because
Hex excludes upstream test files; provenance and hashes are recorded alongside
the fixtures. No HTTP/3, DoQ or adjacent repository changes are included.

## Immutable dependency identity

| Input | Identity |
| --- | --- |
| QUIC package/application | `elixir_quic` / `:elixir_quic`, version `0.2.2` |
| QUIC Hex outer checksum | `2c73402421edf4156db843bbf11fe26aa5cd78eb1ae7acac863ed41fa47e8c74` |
| TLS package/application | `ex_ssl` / `:ex_ssl`, version `0.7.2` |
| TLS Hex outer checksum | `f0f9532a6ac8b2dcb701b491394705df8f10c31f63fc7e5aad157eebb909aecb` |
| Independent peer | `aioquic==1.2.0`, Python 3.12 |
| Local runtime | Elixir 1.18.5, OTP 28.5.0.5 / ERTS 16.4.0.5 |

Both consumer lockfiles record Hex SCM, versions and checksums. The provenance
check also verifies loaded application/module paths and rejects the legacy
`QUIC` module. This prevents an installed Git engine from masking the regression.

## Checks

| Check | Result |
| --- | --- |
| Published consumer before fix | Expected FAIL: `:quic_backend_unavailable` |
| Host lifecycle/writer regressions | PASS: 37 tests, zero failures |
| Default release test command | PASS: 532 tests and 3 doctests, zero failures, 12 excluded; coverage 78.36% |
| Strict dev/test compilation | PASS |
| Published network matrix | PASS: all stream, Retry, negative and lifecycle scenarios |
| Outside-checkout consumers and production releases | PASS: UDP without engine, QUIC echo release and independent collection |
| Formatting and package build | PASS |

Commands:

```sh
mix test --no-cover test/abyss/dispatcher_test.exs test/abyss/quic_test.exs --seed 29092026
mix compile --warnings-as-errors
MIX_ENV=test mix compile --warnings-as-errors
mix test
scripts/phase1/check.sh
scripts/phase1/independent_check.sh
mix format --check-formatted
git diff --check
mix hex.build
```

The network matrix exercises multiple connections, both stream directions,
1 MiB transfer, a 16 KiB write, receive after FIN, bounded consumption, opaque
reset/stop/close errors, Retry on/off/loss/invalid/expired tokens, wrong CA/ALPN,
consumer failures, listener suspension and writer failure/restart. The independent
release check also verifies ordinary UDP has no loadable engine.

Capability limits from [quic-service.md](quic-service.md) remain unchanged.
The pre-existing Credo/Dialyzer CI failures are outside this issue; this change
does not claim to resolve them. The user-owned `03-abyss-plan.md` is preserved.

Recorded evidence: [red reproduction](published-quic-evidence/red.log),
[host regressions](published-quic-evidence/host-tests.log),
[full default suite](published-quic-evidence/full-tests.log),
[Hex provenance](published-quic-evidence/provenance.log),
[network matrix](published-quic-evidence/network.log),
[outside-checkout consumers](published-quic-evidence/independent.log),
[package build](published-quic-evidence/package.log).
The independent sources/builds were copied to
`/tmp/abyss-phase1-consumers.dXLeUU`; no adjacent project was used as an engine
dependency. Each successful network transfer verified 1,048,576 bytes, including
receive-after-FIN behavior. Intentional consumer crashes and writer termination
appear in the fault logs; they are asserted failure-isolation scenarios.

The successful default suite is the release workflow's local counterpart;
excluded integration scenarios are covered by the explicit network/consumer
commands. The GitHub release workflow adds its own Elixir 1.18 / OTP 27 gate.
