# Completed-effects watchdog harness diagnostics

> Historical record. Commands, paths, versions and status below describe the recorded source, not the current checkout. See the [archive index](../../README.md) and [current guides](../../../README.md).

The baseline test could observe `effects_result`, normal helper `DOWN`, and
`work_expired` through selective trace receives without proving their processing
order. Its normal-`DOWN` barrier was too late when expiry had already been
processed. The controlled order reproduction below establishes that gap; the
failed macOS run did not record its event order, so that run's precise ordering
remains unverified.

The repaired test holds the runtime immediately after effects startup, selectively
receives the **actual original timer expiry**, and requeues that same message only
after trace evidence proves the genuine result and monitored normal helper `DOWN`
have entered the runtime mailbox. This establishes result/`DOWN` before the stale
expiry. It preserves `send_timeout: 10`, the resulting 30 ms effects watchdog,
payloads, quotas, and every original assertion. Production code is unchanged.

## Source identity

- Baseline commit: `4645a5ec68049b067c9530a3f1ee670fb557a775`.
- Runtime SHA256: `58f1de0d219a603eb71c2c7cd7fbcf3fd40a7b49c02a420c68f4afa941f6f345`.
- Repaired test SHA256: `aada26b7c9b381afa3feb8fa45534e6822d0c824c776f9b7d3f6e9d439c9df1f`.
- Test-only repair: `test/abyss/datagram_runtime_test.exs`, 19 additions/1 deletion.

## Recorded outcomes

| Evidence log | Actual outcome |
| --- | --- |
| [p6-watchdog-diagnosis-otp27.log](p6-watchdog-diagnosis-otp27.log) | Unchanged baseline test file, covered runtime scope: 23 tests, 0 failures, exit 0. |
| [p6-watchdog-diagnosis-otp28.log](p6-watchdog-diagnosis-otp28.log) | Unchanged baseline test file, covered runtime scope: 23 tests, 0 failures, exit 0. |
| [p6-watchdog-before-repeat.log](p6-watchdog-before-repeat.log) | Baseline targeted test, one scheduler: 101 passing executions; command exit 3 because scoped coverage 31.95% was below the 40% threshold. No export option was supplied. This is not a passing command. |
| [p6-watchdog-order-repro.log](p6-watchdog-order-repro.log) | Controlled baseline harness: result, expiry, then normal helper `DOWN` processing. Exit 2; input credit was already zero at the retained-credit assertion. |
| [p6-watchdog-original-bug-red-otp28.log](p6-watchdog-original-bug-red-otp28.log) | Repaired harness against the original production bug: exit 2, failure at `assert Process.alive?(worker)`. |
| [p6-watchdog-delayed-down-green-otp28.log](p6-watchdog-delayed-down-green-otp28.log) | Repaired harness with helper death delayed 25 ms after its result: 23 tests, 0 failures, 22 excluded, exit 0. |
| [p6-watchdog-harness-green-otp27.log](p6-watchdog-harness-green-otp27.log) | Repaired ordinary source, covered runtime scope: 23 tests, 0 failures, exit 0. |
| [p6-watchdog-harness-green-otp28.log](p6-watchdog-harness-green-otp28.log) | Repaired ordinary source, covered runtime scope: 23 tests, 0 failures, exit 0. |
| [p6-watchdog-harness-repeat-otp28.log](p6-watchdog-harness-repeat-otp28.log) | Repaired targeted test, one scheduler, coverage exported: 101 passing executions, exit 0. Mix performs the initial execution plus 100 repetitions. |

The three mutated-runtime diagnostics reload `Abyss.DatagramRuntime` with
`Code.compile_string/1`. **Their module coverage is invalid**, including the
commands that request coverage export. They provide behavioral discrimination,
not coverage evidence. The ordinary unmodified-runtime OTP 27/28 runs provide the
covered verification. Expected component-exit error logs in those full scoped
runs did not cause test failures.

## Portable diagnostic source generation

Run from the UDP worktree root with Python 3 and Git available. This generates
temporary copies from tracked source and the recorded baseline commit; none of
the historical `/tmp` source files is needed. The hashes prevent accidental
reproduction against different source bytes. Only the generated copies are
mutated; repository production and test files are read-only.

```sh
watchdog_diag_dir=$(mktemp -d)
export WATCHDOG_DIAG_DIR="$watchdog_diag_dir"
python3 - <<'PY'
from pathlib import Path
import hashlib
import os
import subprocess

out = Path(os.environ["WATCHDOG_DIAG_DIR"])
runtime = Path("lib/abyss/datagram_runtime.ex").read_text()
repaired = Path("test/abyss/datagram_runtime_test.exs").read_text()
assert hashlib.sha256(runtime.encode()).hexdigest() == \
    "58f1de0d219a603eb71c2c7cd7fbcf3fd40a7b49c02a420c68f4afa941f6f345"
assert hashlib.sha256(repaired.encode()).hexdigest() == \
    "aada26b7c9b381afa3feb8fa45534e6822d0c824c776f9b7d3f6e9d439c9df1f"
baseline = subprocess.run(
    ["git", "show", "4645a5ec68049b067c9530a3f1ee670fb557a775:"
     "test/abyss/datagram_runtime_test.exs"],
    check=True, text=True, capture_output=True,
).stdout

def replace_once(text, old, new):
    assert text.count(old) == 1, old
    return text.replace(old, new)

def diagnostic(name, runtime_copy, test_copy):
    runtime_name = f"{name}-runtime.ex"
    (out / runtime_name).write_text(runtime_copy)
    prefix = (
        'Code.compile_string(File.read!(Path.join(__DIR__, '
        f'"{runtime_name}")))\n'
    )
    (out / f"{name}_test.exs").write_text(prefix + test_copy)

# Restore exactly the old normal-DOWN branch, retaining the repaired test.
normal_down = """      {:effects, {_outcomes, _stop_reason}, :normal} ->
        cancel(worker.watchdog)
        finish_effects(key, put_worker(state, key, %{worker | watchdog: nil}))"""
old_branch = """      {:effects, {_outcomes, _stop_reason}, :normal} ->
        finish_effects(key, state)"""
diagnostic("original-bug", replace_once(runtime, normal_down, old_branch), repaired)

# Simulate delayed process scheduling after the terminal result and before DOWN.
send_result = "        _ = send(runtime, {:effects_result, key, token, outcomes, stop_reason})"
delayed_runtime = replace_once(runtime, send_result, send_result + "\n        Process.sleep(25)")
diagnostic("delayed-down", delayed_runtime, repaired)

# Reproduce the baseline harness's invalid ordering with that same delay.
# Hold its runtime for 60 ms at result reception, so the original real 30 ms
# expiry queues before the delayed helper's normal DOWN is processed.
down_hook = "             {:in, {:DOWN, _, :process, helper, :normal}} when helper != worker ->"
result_hook = """             {:in, {:effects_result, _, _, _, _}} ->
               Process.send_after(self(), :continue_diagnostic_result, 60)
               receive do: (:continue_diagnostic_result -> held)

"""
ordered = replace_once(baseline, down_hook, result_hook + down_hook)
debug_hook = "fn held, event, _name ->\n           case event do"
ordered = replace_once(
    ordered, debug_hook,
    "fn held, event, _name ->\n"
    '           IO.inspect({System.monotonic_time(:microsecond), event}, '
    'label: "WATCHDOG_EVENT", limit: 6)\n'
    "           case event do",
)
diagnostic("order-repro", delayed_runtime, ordered)
(out / "baseline_test.exs").write_text(baseline)
print(out)
PY
```

The 25 ms helper delay and 60 ms diagnostic hold are induced scheduling controls
in temporary copies, not production changes or acceptance deadline increases.
The `order-repro` expected failure establishes a possible ordering gap; it does
not claim the same event order was directly observed on macOS.

## Diagnostic commands

The recorded OTP 28 runs used `ERL_FLAGS='+S 8:8'` and
`MIX_BUILD_PATH=/tmp/abyss-p6-otp28-final`; repetition runs used `+S 1:1`. These
commands reproduce their exact test flags with the portable generated filenames.
Each diagnostic prefix adds one source line, putting the targeted test at 468.
The repaired repository test starts at 467.

```sh
# Expected original-bug RED, exit 2.
ERL_FLAGS='+S 8:8' MIX_BUILD_PATH=/tmp/abyss-p6-otp28-final \
  mix test "$WATCHDOG_DIAG_DIR/original-bug_test.exs:468" \
  --cover --export-coverage watchdog-original-bug-red --seed 953627

# Expected delayed actual-DOWN GREEN, exit 0; mutated-module coverage is invalid.
ERL_FLAGS='+S 8:8' MIX_BUILD_PATH=/tmp/abyss-p6-otp28-final \
  mix test "$WATCHDOG_DIAG_DIR/delayed-down_test.exs:468" \
  --cover --export-coverage watchdog-delayed-down-green --seed 953627

# Expected baseline ordering RED, exit 2, without coverage.
ERL_FLAGS='+S 8:8' MIX_BUILD_PATH=/tmp/abyss-p6-otp28-final \
  mix test "$WATCHDOG_DIAG_DIR/order-repro_test.exs:468" \
  --no-cover --seed 953627

# Historical baseline repeat: all assertions passed, command exit 3 on coverage.
ERL_FLAGS='+S 1:1' MIX_BUILD_PATH=/tmp/abyss-p6-otp28-final \
  mix test "$WATCHDOG_DIAG_DIR/baseline_test.exs:467" \
  --cover --repeat-until-failure 100 --seed 953627
```

## Ordinary source verification commands

These commands do not reload or mutate the runtime. The two `diagnosis` logs used
the baseline test file before the repair, with export names
`watchdog-diagnosis-otp27` and `watchdog-diagnosis-otp28`; the commands and results
otherwise match the corresponding full runtime scope below.

```sh
# From the primary checkout; its devenv supplies OTP 27.
devenv shell -- bash -c 'cd .trees/udp-runtime; mix test test/abyss/datagram_runtime_test.exs --cover --export-coverage watchdog-harness-otp27 --seed 953627'

# From the UDP worktree; system runtime supplies OTP 28.
ERL_FLAGS='+S 8:8' MIX_BUILD_PATH=/tmp/abyss-p6-otp28-final \
  mix test test/abyss/datagram_runtime_test.exs \
  --cover --export-coverage watchdog-harness-otp28 --seed 953627

ERL_FLAGS='+S 1:1' MIX_BUILD_PATH=/tmp/abyss-p6-otp28-final \
  mix test test/abyss/datagram_runtime_test.exs:467 \
  --cover --export-coverage watchdog-harness-repeat \
  --repeat-until-failure 100 --seed 953627

ERL_FLAGS='+S 8:8' MIX_BUILD_PATH=/tmp/abyss-p6-otp28-final \
  mix format --check-formatted test/abyss/datagram_runtime_test.exs
git diff --check -- test/abyss/datagram_runtime_test.exs
```

No tests were repeated when this document and the log copies were prepared.
