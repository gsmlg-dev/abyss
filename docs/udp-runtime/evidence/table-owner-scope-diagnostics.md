# TableOwner scope-cleanup test ordering

Remote diagnostic run `38505262533`, source
`2c896247cc9a6282c84dc67dc9cbd76a0636aaa7`, fails the unchanged abrupt
server-death test on Linux OTP27 with `endpoint cleanup did not complete`.
Raw evidence: `p6-remote-blocked-writer-observer-fail.log` and
`p6-remote-blocked-writer-observer.json`. That job reports 195 tests,
1 failure, 3 excluded and exit 2. No remote TableOwner event trace exists;
the exact remote scheduling order is not asserted from that log alone.

`wait_for_cleanup(server, socket, 100)` is a count of 100 immediate system-state
probes, **not a 100 ms deadline**. Neither the asynchronous `Process.exit`
call nor `:sys.get_state` acknowledges handling of the server's monitor DOWN.
TableOwner synchronously calls `Listener.clear_desired`, `Telemetry.clear_scope`
and removes its scope monitor inside the matching DOWN handler.

## Controlled ordering evidence

`p6-table-owner-scope-ordering-otp27.log` records an isolated, owned OTP27 BEAM.
Only that BEAM's TableOwner is temporarily suspended. The actual server is
killed, and the diagnostic observes its native monitor DOWN. All 100 original
system-state probes then complete in 922 microseconds without scope cleanup;
the exact native DOWN for TableOwner's registered scope monitor is queued.
After resuming TableOwner, an observer sees the real matching DOWN handler's
`:noreply` completion, and the original metric, membership and scope assertions
pass. The diagnostic exits 0 because this controlled failure of the probes is
the expected result. It is ordering evidence, not a failed acceptance test or
proof of the precise remote interleaving.

No fake DOWN, sleeps, network changes or timer widening are used. The script's
`after` block resumes its owned TableOwner even on diagnostic failure. The
portable script is preserved as `table-owner-scope-observe.exs.txt`; no unowned
application process is suspended or modified.

## Test-only repair and checks

Only `test/abyss/table_owner_scope_test.exs` changes. Before the original
100-probe call, the test now waits for actual server DOWN and an acknowledgement
emitted after TableOwner processes the DOWN matching its actual scope-monitor
reference. The `:sys` debug observer removes itself with `:done` after that
callback's completion. Each new `assert_receive` retains ExUnit's default
100 ms bound. No production code, polling count or existing assertion changes.

Every original source line remains in order. The complete polling helper is
byte-identical to source `2c896247...`, SHA256
`a3a64a60725bffbca5ef732e0694255aa15957bb2cef523a528e175e496922d9`.
The acknowledgement certifies handling of this scoped ETS cleanup event. It
does not claim whole-runtime or native-resource reclamation from zero counts.

| Evidence | Exit | Result |
|---|---:|---|
| `p6-table-owner-scope-green-otp27.log` | 0 | Covered scoped test: 1 test, 0 failures |
| `p6-table-owner-scope-green-otp28.log` | 0 | Covered scoped test: 1 test, 0 failures |

Scoped format and diff checks pass. Current scope-cleanup repair round 1
succeeded. Final full suites and actual remote acceptance remain parent-owned.

## Exact commands

The diagnostic and OTP27 scoped check run from the primary checkout in devenv
Elixir1.18.4 / OTP27 / ERTS15.2.7.4, eight schedulers:

```sh
cp .trees/udp-runtime/docs/udp-runtime/evidence/table-owner-scope-observe.exs.txt /tmp/abyss-table-owner-cleanup-observe.exs
devenv shell -- bash -c 'cd .trees/udp-runtime && ERL_FLAGS="+S 8:8" mix run /tmp/abyss-table-owner-cleanup-observe.exs' > /tmp/abyss-table-owner-cleanup-observe-otp27.log 2>&1
devenv shell -- bash -c 'cd .trees/udp-runtime && ERL_FLAGS="+S 8:8" mix test test/abyss/table_owner_scope_test.exs --seed 953627 --cover --export-coverage table-owner-scope-green-otp27' > /tmp/abyss-table-owner-scope-green-otp27.log 2>&1
```

OTP28 uses system Elixir1.18.5 / OTP28 / ERTS16.4.0.5 and the final build path.
Run from the candidate worktree:

```sh
MIX_BUILD_PATH=/tmp/abyss-p6-otp28-final ERL_FLAGS='+S 8:8' mix test test/abyss/table_owner_scope_test.exs --seed 953627 --cover --export-coverage table-owner-scope-green-otp28 > /tmp/abyss-table-owner-scope-green-otp28.log 2>&1
MIX_BUILD_PATH=/tmp/abyss-p6-otp28-final ERL_FLAGS='+S 8:8' mix format --check-formatted test/abyss/table_owner_scope_test.exs
git diff --check -- test/abyss/table_owner_scope_test.exs
```

All three raw logs and the portable diagnostic script are byte-preserved.
