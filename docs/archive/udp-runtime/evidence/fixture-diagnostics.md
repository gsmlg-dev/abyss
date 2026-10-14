# Completed-effect fixture ordering

> Historical record. Commands, paths, versions and status below describe the recorded source, not the current checkout. See the [archive index](../../README.md) and [current guides](../../../README.md).

The original blocked-Writer credit test and zero-input runtime-death test require
a normally completed invocation while its accepted Writer send remains blocked.
Their assertions concern retained output credit and cleanup after input retirement.
Their setup previously raced the real 30 ms effects deadline: acceptance by the
Writer does not certify a terminal effects result or the matching normal helper
`DOWN`. An unfinished helper may legitimately expire and hard-kill the worker
without invoking its normal termination callback.

The shared test-only `completed_effect_fixture/4` now establishes that premise.
It holds the runtime immediately after effects startup, captures the actual input
slot and helper monitor, and certifies the genuine terminal unknown-send result
and matching normal helper `DOWN` through runtime receive traces. It selectively
holds the **actual original expired timer message**, then requeues that same
message after the already-queued result/`DOWN`. It creates no synthetic result,
`DOWN`, or expiry, and neither cancels nor replaces the production timer.

This deliberately controls completion-versus-expiry processing order in fixture
setup. It is not proof that an unfinished helper always finishes within 30 ms.
`send_timeout: 10`, the resulting 30 ms watchdog, the existing termination waits,
all original assertions, payloads, quotas, and runtime kill operations remain
unchanged. The zero-input test still waits for actual worker `DOWN`, retirement of
the exact captured input slot in TableOwner, and zero input with one blocked
egress entry before killing the runtime and checking actual component deaths and
lookup removal. Production code and unfinished-effect deadline behavior are
unchanged. The existing queued-expiry regression body is byte-for-byte unchanged.
The temporary diagnostic observer was removed from the original credit test.

## Actual macOS observation

[Run 38505262533](https://github.com/gsmlg-dev/abyss/actions/runs/38505262533),
source `2c896247cc9a6282c84dc67dc9cbd76a0636aaa7`, recorded the original
instrumented blocked-Writer test passing. The ordered
`BLOCKED_WRITER_ORDER` records in
[p6-remote-blocked-writer-observer-fail.log](p6-remote-blocked-writer-observer-fail.log)
show:

| Sequence | Time after effects startup | Processed event and resulting state |
| --- | --- | --- |
| 1 | 0 ms | Invocation result starts effects, watchdog reference ends `132848`. |
| 3 | 16.984 ms | Genuine terminal `effects_result`, unknown send receipt. |
| 5 | 17.007 ms | Matching helper monitor `132847`, helper `0.984.0`, normal `DOWN`; effects becomes closing and obtains distinct termination watchdog `132857`. |
| 7 | 17.066 ms | Worker `0.983.0` normal `DOWN`; input count changes 1 to 0. |

No `work_expired` or `cleanup_expired` occurred in that recorded path. It confirms
the production completion/retirement contract on actual macOS traffic. The full
workflow was still red: the zero-input fixture failed at its termination assertion
**before** its deliberate runtime kill, and its event order was not instrumented.
The healthy blocked-Writer trace does not attribute that separate failure. The
controlled comparison below proves the old fixture's completion premise can be
invalidated by legitimate helper scheduling delay; it does not claim that this
precise event order was directly observed in the failed macOS zero-input case.
The complete run metadata is retained in
[p6-remote-blocked-writer-observer.json](p6-remote-blocked-writer-observer.json).

## Local evidence and source identity

- Baseline before fixture edits: `2c896247cc9a6282c84dc67dc9cbd76a0636aaa7`.
- Final test SHA256: `8cede7928925d99afdfd218a6992115885e35f42b25666afa42fd394c0ffe93c`.
- Unchanged runtime SHA256: `58f1de0d219a603eb71c2c7cd7fbcf3fd40a7b49c02a420c68f4afa941f6f345`.
- Python preservation checks: original assertion sequences in both affected tests
  unchanged; corrected queued-expiry regression body unchanged; observer removed.
- Formatting and `git diff --check`: PASS.

| Evidence | Actual result |
| --- | --- |
| [p6-fixture-green-otp27.log](p6-fixture-green-otp27.log) | Ordinary runtime, covered complete runtime-test scope: 23 tests, 0 failures, exit 0. |
| [p6-fixture-green-otp28.log](p6-fixture-green-otp28.log) | Ordinary runtime, covered complete runtime-test scope: 23 tests, 0 failures, exit 0. |
| [p6-fixture-original-bug-red-otp28.log](p6-fixture-original-bug-red-otp28.log) | Restored original production bug in a temporary runtime copy: unchanged queued-expiry regression fails at `Process.alive?(worker)`, 23 tests/1 failure/22 excluded, exit 2. |
| [p6-fixture-delayed-original-red-otp28.log](p6-fixture-delayed-original-red-otp28.log) | Original zero-input setup with a 25 ms delay between helper result and helper death: missing termination message, 23 tests/1 failure/22 excluded, exit 2. This exposes the normal-completion premise, not a new production bug. |
| [p6-fixture-delayed-green-otp28.log](p6-fixture-delayed-green-otp28.log) | Both repaired fixtures with that same delayed runtime: 23 tests/0 failures/21 excluded, exit 0. |

The three diagnostic commands use `Code.compile_string/1` to reload a mutated
runtime inside an isolated test VM and run with `--no-cover`. Their runtime module
coverage would be **invalid**; they are behavioral comparisons, not coverage
evidence. Only the two ordinary-runtime covered runs establish coverage evidence.
Expected runtime-kill error logs in the zero-input cleanup case are not test
failures. No further tests were run after the final controlled comparison.

## Portable diagnostic generation

Run from the UDP worktree root. Only temporary copies are written; no historical
`/tmp` source file is required. Hash guards ensure the exact tested fixture and
runtime bytes are used. The original production bug and scheduling delay are
separate mutations; neither modifies repository production files.

```sh
fixture_diag_dir=$(mktemp -d)
export FIXTURE_DIAG_DIR="$fixture_diag_dir"
python3 - <<'PY'
from pathlib import Path
import hashlib
import os

out = Path(os.environ["FIXTURE_DIAG_DIR"])
runtime = Path("lib/abyss/datagram_runtime.ex").read_text()
test = Path("test/abyss/datagram_runtime_test.exs").read_text()
assert hashlib.sha256(runtime.encode()).hexdigest() == \
    "58f1de0d219a603eb71c2c7cd7fbcf3fd40a7b49c02a420c68f4afa941f6f345"
assert hashlib.sha256(test.encode()).hexdigest() == \
    "8cede7928925d99afdfd218a6992115885e35f42b25666afa42fd394c0ffe93c"

def replace_once(text, old, new):
    assert text.count(old) == 1, old
    return text.replace(old, new)

def diagnostic(name, runtime_name, source):
    prefix = ('Code.compile_string(File.read!(Path.join(__DIR__, '
              f'"{runtime_name}")))\n')
    (out / f"{name}_test.exs").write_text(prefix + source)

normal_down = """      {:effects, {_outcomes, _stop_reason}, :normal} ->
        cancel(worker.watchdog)
        finish_effects(key, put_worker(state, key, %{worker | watchdog: nil}))"""
old_branch = """      {:effects, {_outcomes, _stop_reason}, :normal} ->
        finish_effects(key, state)"""
(out / "original-bug-runtime.ex").write_text(
    replace_once(runtime, normal_down, old_branch))
diagnostic("original-bug", "original-bug-runtime.ex", test)

send_result = "        _ = send(runtime, {:effects_result, key, token, outcomes, stop_reason})"
(out / "delayed-down-runtime.ex").write_text(
    replace_once(runtime, send_result, send_result + "\n        Process.sleep(25)"))
diagnostic("delayed-fixture", "delayed-down-runtime.ex", test)

# Restore only the original fixture setup. All its original assertions remain.
old_test = replace_once(
    test,
    '    completed_effect_fixture(server, client, port, "blocked-send")',
    '    :ok = packet(client, port, "blocked-send")',
)
setup = """    %{runtime: runtime, admission: admission, slot: token} =
      completed_effect_fixture(server, client, port, "unknown-send")

    assert_receive {:writer_blocked, writer}"""
original = """    [listener] = server |> Abyss.Server.listener_pool_pid() |> Abyss.ListenerPool.listener_pids()
    runtime = :sys.get_state(listener).runtime
    :ok = packet(client, port, "unknown-send")
    assert_receive {:writer_blocked, writer}
    %{admission: admission, inputs: inputs} = :sys.get_state(runtime)
    token = inputs |> Map.values() |> hd() |> Map.fetch!(:slot)"""
old_test = replace_once(old_test, setup, original)
diagnostic("delayed-original-fixture", "delayed-down-runtime.ex", old_test)
print(out)
PY
```

## Exact test flags

The diagnostic prefix adds one line: original-bug queued-expiry test at 535,
blocked-Writer fixture at 509, and zero-input fixture at 855.

```sh
# From the primary checkout, using its OTP 27 devenv.
devenv shell -- bash -c 'cd .trees/udp-runtime; mix test test/abyss/datagram_runtime_test.exs --cover --export-coverage completed-effects-fixtures-otp27 --seed 953627'

# From the UDP worktree, using system OTP 28.
ERL_FLAGS='+S 8:8' MIX_BUILD_PATH=/tmp/abyss-p6-otp28-final \
  mix test test/abyss/datagram_runtime_test.exs \
  --cover --export-coverage completed-effects-fixtures-otp28 --seed 953627

# Expected original production-bug RED, exit 2.
ERL_FLAGS='+S 8:8' MIX_BUILD_PATH=/tmp/abyss-p6-otp28-final \
  mix test "$FIXTURE_DIAG_DIR/original-bug_test.exs:535" --no-cover --seed 953627

# Expected original fixture-premise RED under induced helper delay, exit 2.
ERL_FLAGS='+S 8:8' MIX_BUILD_PATH=/tmp/abyss-p6-otp28-final \
  mix test "$FIXTURE_DIAG_DIR/delayed-original-fixture_test.exs:855" \
  --no-cover --seed 953627

# Both repaired fixtures GREEN under the identical helper delay, exit 0.
ERL_FLAGS='+S 8:8' MIX_BUILD_PATH=/tmp/abyss-p6-otp28-final \
  mix test "$FIXTURE_DIAG_DIR/delayed-fixture_test.exs:509" \
  "$FIXTURE_DIAG_DIR/delayed-fixture_test.exs:855" --no-cover --seed 953627
```
