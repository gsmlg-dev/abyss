# P1 correctness checkpoint

Baseline `9b710e6480900e16e304f40e63623aff8c922e19`; worktree `.trees/udp-runtime`, branch `codex/udp-runtime`. Functional acceptance G1 passes on Linux OTP 27 and OTP 28 fresh-VM matrices, with the scoped suite on devenv OTP 27. Broader QA and runtime/platform acceptance remain owned by P6.

## Changes

All three single-response helpers (Client, UDP, UDP.Unicast) resolve the chosen peer once and use one monotonic deadline established before sending. Unicast defaults to exact remote address/port. Multicast and limited-broadcast destinations retain any-peer response policy. The explicit `response_policy: :any` option supports intentional cross-peer responses and directed-broadcast policies without silently disabling normal unicast validation. Transport `/2` and `/3` arities/result shapes remain; `/4` adds explicit policy/socket options. Client retains payload results; transport helpers retain complete receive tuples. Empty datagrams, send errors and scoped-peer distinctions are preserved. DNS resolution/opening are outside the response budget. Scope-bearing expectations never match a scope-less source tuple.

`Core.effective_backend/1` uses the first explicit selector, otherwise classifies a temporary socket opened through public GenUDP. It closes that socket immediately and caches the node-default identity in an Abyss-owned persistent term. Concurrent first resolutions may each probe; later operations use the immutable cache. This avoids private OTP APIs and mutable application settings. Normalization freezes the explicit resolved selector first; Client scoped validation and Multicast strict filtering use it. Runtime getters/setters/send checks use the already-open socket's actual identity. Backend conversions preserve already-normalized raw options. Canonical membership aliases are deduplicated after resolution, making nested normalization idempotent.

The Linux inet named `multicast_if` getter was additionally found to misdecode the interface address (raw getter and actual wire traffic remained correct). Core now uses the verified Linux four-byte raw getter on inet too, preserving the existing socket-backend workaround.

## Evidence

Commands run from the primary checkout, entering the worktree through its configured environment:

```sh
devenv shell -- bash -c 'cd .trees/udp-runtime && mix test test/abyss/udp_peer_validation_test.exs test/abyss/udp_backend_resolution_test.exs test/abyss/client_regression_test.exs test/abyss/transport/udp --no-cover'
devenv shell -- bash -c 'cd .trees/udp-runtime && scripts/udp/backend_boot.sh'
```

- `evidence/p1-red-peer.log`: baseline 13 tests, 10 failures, exit 2. Nine actual provenance/deadline failures plus the initially missing shared exchange helper.
- `evidence/p1-red-backend.log`: fresh socket-default VM, strict filtering returned `:einval` instead of the capability rejection, exit 1.
- `evidence/p1-red-idempotence.log`: equivalent IPv6 membership selectors produced duplicate canonical joins on first normalization, exit 2.
- `evidence/p1-green-otp27.log`: final 226 scoped tests, zero failures, exit 0.
- `evidence/p1-backend-otp27.log` and `evidence/p1-backend-otp28.log`: five separate VMs on each runtime: unset, inet default, socket default, explicit inet overriding socket default, explicit socket overriding inet default; all exit 0. Real helper exchanges reject wrong source ports. Real multicast bind/join/send/receive/get/set/leave and scoped-send/strict-filter capability decisions agree with effective backend selection.
- Scoped format check and `git diff --check`: exit 0.
- `evidence/p1-source-sha256.log`: source hashes for the tested implementation and regression programs.

## Remaining QA and limits

Scoped strict Credo diff command (exact owned files):

```sh
devenv shell -- bash -c 'cd .trees/udp-runtime && mix credo diff --from-git-ref HEAD --strict --files-included "lib/abyss/client.ex" --files-included "lib/abyss/transport/udp.ex" --files-included "lib/abyss/transport/udp/core.ex" --files-included "lib/abyss/transport/udp/multicast.ex" --files-included "lib/abyss/transport/udp/unicast.ex"'
```

`evidence/p1-credo-diff.log`: final exit 0, no new findings in the five owned source files. Minor QA refactors alias transport modules and flatten nesting. The prior seven P1 findings are resolved. The larger UDP glob included the concurrently authored Native adapter; its findings were reported to that file's owner and excluded from this P1 report. Functional repair history: one unsuccessful repair followed by a successful repair; subsequent requested minor QA refactors passed. No commits/pushes; all worker commands finished.

OTP 28 matrix command uses system Elixir 1.18.5 / ERTS 16.4.0.5 and an isolated build path:

```sh
MIX_BUILD_PATH=/tmp/abyss-p1-otp28-dev scripts/udp/backend_boot.sh
```

Actual ancillary provenance is proven on supported GenUDP inet receive forms. This OTP 27 build rejects GenUDP socket named `recvttl`, `recvtos` and `recvtclass` with `:einval`; raw kernel enabling alone does not switch the compatibility receive method to return ancillary tuples. Plain IPv4/IPv6 provenance on both drivers passes. Native metadata/scoped wire proof belongs to P4; the GenUDP socket scoped-send rejection is not positive scoped-send evidence. OTP 28 fresh-VM backend acceptance passes; macOS is not run by this P1 worker and remains owned by P6.
