# Dispatcher writer-death timing diagnostic

> Historical record. Commands, paths, versions and status below describe the recorded source, not the current checkout. See the [archive index](../../README.md) and [current guides](../../../README.md).

The unchanged writer-death test at `test/abyss/dispatcher_test.exs:279` failed
its 100 ms `assert_receive` in two ordinary OTP28 full-suite runs, seed 953627:
`p6-full-otp28-watchdog-harness-final.log` and
`p6-full-otp28-watchdog-harness-serial.log`. The mailbox was empty. A bounded
diagnostic reproduced the same assertion failure and located the observed
delay after Dispatcher cleanup, inside OTP's crash-report path.

## Source and build attribution

Worktree `.trees/udp-runtime`, branch `codex/udp-runtime`; repair baseline
`141bffa6c730c78306abbd8e63c5a58eeda4cc79`. Production Dispatcher source is
byte-identical at `e12045162438cb9df43bd2da868d27d27e75bca2`,
`4645a5ec68049b067c9530a3f1ee670fb557a775`, the repair baseline, and the
diagnostic worktree. SHA256 of `lib/abyss/datagram_dispatcher.ex`:
`d8defa29e5bf0d388a8b4c14c594662fd4e2836bf99e991d9eb44586ba8d30b8`.

The initial diagnostics reused `/tmp/abyss-p6-otp28`, whose Listener artifacts
were stale. They are **not selected-source full QA**. Subsequent verification
used `/tmp/abyss-p6-otp28-final`, the actual final OTP28 build. Independent
`:beam_lib.md5/1` comparisons found identical code MD5s for Dispatcher,
Admission and Writer in both build paths:

| Module | Code MD5 in both builds |
|---|---|
| `Abyss.Dispatcher` | `86e63379da3d0b5c21ad565b79432a03` |
| `Abyss.Dispatcher.Admission` | `09e638a7332ec01f871777a3ca3783d0` |
| `Abyss.Dispatcher.Writer` | `9776721de2bbae52e3fd7f8800d472cc` |

## Observed ordering and limits

In `p6-writer-death-red-full-trace-otp28.log`, Dispatcher `#PID<0.448.0>`
receives the actual Writer `:killed` EXIT, returns the stop tuple, and completes
`Dispatcher.terminate/2` and both child-cleanup calls in about 2.92 ms.
Admission's actual normal DOWN is observed. OTP `gen_server:error_info/7`
then takes about 312.06 ms before returning; Dispatcher subsequently produces
an actual monitor DOWN with reason `{:writer_exit, :killed}`. The unchanged
100 ms assertion has already failed. This trace locates the observed delay in
reporting after cleanup; it does not isolate formatting, handler I/O or
scheduling costs within that reporting function.

The full diagnostic exits 2 with 648 tests, 3 doctests and **5 failures**.
Besides writer-death, four DatagramRuntime tests fail with `ArgumentError`
(`invalid spec for pid or port`) at their own `:erlang.trace` calls: completed
effects settlement, absolute stop, idle expiry and unexpected worker death.
The diagnostic globally assigns a legacy tracer to new processes, conflicting
with those tests' tracer ownership. Together with the stale Listener build,
this limits the full run to attribution evidence; none of its other outcomes
are accepted as final-source QA or source regressions.

The initial scoped trace before log capture exits 0: 19 tests, 18 excluded,
0 failures; its observed Dispatcher EXIT-to-DOWN interval is about 10.7 ms.
The correct-build focused trace after capture exits 0 with the same counts;
expected Dispatcher DOWN is observed about 13.3 ms after its Writer EXIT
handler begins. Call/return timestamps come from BEAM monotonic tracing;
DOWN timestamps are observer receipt times and include observer scheduling
and trace-output overhead. The full diagnostic's Writer monitor was attached
after death and reports `:noproc`; the actual killed reason is independently
present in Dispatcher EXIT and Admission DOWN messages. No fake EXIT/DOWN
messages or process suspension were used.

## Narrow test repair and accepted verification

The sole source change is `@tag :capture_log` on the expected writer-death
test. A byte comparison against the repair baseline confirms the entire
original test body is unchanged, including workload, pinned reason, capability
assertion and default 100 ms receive deadline. No production Logger or
Dispatcher change was made.

ExUnit's log-capture hook removes the default logger handler while capture is
active, records the expected crash report, and restores the handler when the
last capture ends. Capturing that expected report changes the test's logging
environment. The following ordinary checks pass after this one-tag repair:

| Evidence | Exit | Actual result |
|---|---:|---|
| `p6-writer-death-capture-scoped-otp27.log` | 0 | 19 tests, 0 failures |
| `p6-writer-death-capture-scoped-otp28.log` | 0 | 19 tests, 0 failures |
| `p6-writer-death-capture-full-otp28.log` | 0 | 648 tests + 3 doctests, 0 failures |

Scoped format/diff checks and test-body byte preservation also pass. Repair
round 1 succeeded. These results do not establish a universal 100 ms process
exit guarantee, identify the inner reporting bottleneck, or replace other
final-source platform/consumer acceptance gates.

## Exact commands

Diagnostic and OTP28 commands below ran from the candidate worktree with system
Elixir 1.18.5 / OTP28 / ERTS16.4.0.5, eight schedulers. The preserved portable
tracer has no checkout/build paths embedded. Copy it to its original temporary
path before invoking the historical diagnostic command:

```sh
cp docs/udp-runtime/evidence/writer-death-trace.exs.txt /tmp/abyss-writer-death-trace.exs

# Historical red diagnostic: stale build, global tracer conflicts; NOT full QA.
MIX_ENV=test MIX_BUILD_PATH=/tmp/abyss-p6-otp28 ERL_FLAGS='+S 8:8' mix run --no-start --no-compile /tmp/abyss-writer-death-trace.exs --no-compile --no-cover --include integration --seed 953627 > /tmp/abyss-writer-death-full-trace-otp28.log 2>&1

# Correct-build focused trace after capture tag, not ordinary full QA.
MIX_ENV=test MIX_BUILD_PATH=/tmp/abyss-p6-otp28-final ERL_FLAGS='+S 8:8' mix run --no-start --no-compile /tmp/abyss-writer-death-trace.exs test/abyss/dispatcher_test.exs:280 --no-compile --no-cover --seed 953627 > /tmp/abyss-writer-death-capture-scoped-trace-otp28.log 2>&1

# Ordinary correct-build verification, without diagnostic tracing.
MIX_BUILD_PATH=/tmp/abyss-p6-otp28-final ERL_FLAGS='+S 8:8' mix test test/abyss/dispatcher_test.exs --no-cover --seed 953627 > /tmp/abyss-writer-death-capture-scoped-otp28.log 2>&1
MIX_BUILD_PATH=/tmp/abyss-p6-otp28-final ERL_FLAGS='+S 8:8' mix test --include integration --no-cover --seed 953627 > /tmp/abyss-writer-death-capture-full-otp28.log 2>&1
MIX_BUILD_PATH=/tmp/abyss-p6-otp28-final ERL_FLAGS='+S 8:8' mix format --check-formatted test/abyss/dispatcher_test.exs
git diff --check -- test/abyss/dispatcher_test.exs
```

OTP27 scoped verification ran from the primary checkout through devenv
(Elixir1.18.4 / OTP27 / ERTS15.2.7.4):

```sh
devenv shell -- bash -c 'cd .trees/udp-runtime && ERL_FLAGS="+S 8:8" mix test test/abyss/dispatcher_test.exs --no-cover --seed 953627' > /tmp/abyss-writer-death-capture-scoped-otp27.log 2>&1
```

The initial before-capture scoped command used the stale build and location
279. Its script initially selected `gen_server:error_info/8`, which does not
match OTP28's reporting function; the preserved final script uses arity 7.
All raw diagnostic logs were copied byte-for-byte. The tracer is deliberately
stored as `.exs.txt` so evidence preservation does not add executable project
source or interfere with ordinary tests. Do not run it alongside tests that
own legacy tracer slots, or treat a diagnostic rerun as an acceptance check.
