# Resource and performance measurements

> Historical record. Commands, paths, versions and status below describe the recorded source, not the current checkout. See the [archive index](../README.md) and [current guides](../../README.md).

These are controlled workload results and sampled process/mailbox observations. They do not establish whole-VM memory limits, kernel drop counts, UDP delivery guarantees or a universal throughput number.

## Paired legacy steady workload

Linux x86_64, devenv Elixir 1.18.4 / OTP27 / ERTS15.2.7.4, eight schedulers. Baseline is `9b710e6480900e16e304f40e63623aff8c922e19`; measured candidate identity is recorded in `evidence/source-4645a5ec-sha256.log` and the performance JSON. The final test-harness revision changes only the regression test; application and benchmark bytes remain identical. The exact same `steady.exs` script runs against both checkouts, one listener, 64-byte payload, 500 warmup and 3000 sequential request/replies per sample. Compilation completes before samples. Three repetitions alternate baseline/candidate serially with no concurrent tests or builds. All six exchanges loops pass exact peer/port/payload assertions.

| Median of three samples | Baseline legacy | Candidate legacy |
|---|---:|---:|
| Exchanges/second | 10,082 | 9,391 |
| Per-sample median latency,µs | 98 | 104 |
| Per-sample p95 latency,µs | 134 | 147 |
| Per-sample p99 latency,µs | 150 | 171 |

Candidate legacy throughput is about 6.9% lower; latency median about 6.1% higher. This is a reported regression, not a performance improvement claim. Candidate shared ownership/admission cleanup has additional monitored accounting, but these samples do not independently profile or assign causality. No arbitrary listener-pool increase is proposed. Earlier concurrent test/build samples (`baseline-steady.log`, `p6-steady-*.log`) are retained as historical runs and are not controlled comparisons.

Reproduce from the primary checkout, with no competing heavy jobs:

```sh
devenv shell -- python3 .trees/udp-runtime/scripts/udp/compare_steady.py   /home/gao/Workspace/gsmlg-dev/abyss
```

The script compiles baseline in `/tmp/abyss-p6-steady-baseline`, candidate in its own `_build`, and writes all six `p6-steady-paired-*.log` files plus `p6-steady-paired.json`. Raw logs include process counts and end-of-run owner mailbox samples. Medians are of three samples, not percentiles aggregated over all 9000 requests.

## New API workload

Three serial samples per policy with the same 500/3000/64-byte workload all pass. `p6-steady-controlled.json` and nine raw logs record medians:

| Policy | Exchanges/second | Median latency,µs | p95,µs | p99,µs |
|---|---:|---:|---:|---:|
| per_datagram | 3,431 | 286 | 376 | 430 |
| endpoint | 3,736 | 262 | 353 | 409 |
| keyed | 3,382 | 288 | 389 | 440 |

Reproduce each policy three times using `ERL_FLAGS='+S 8:8' ABYSS_STEADY_MODE=endpoint mix run --no-compile scripts/udp/steady.exs`, substituting `per_datagram` and `keyed`, in the OTP27 devenv. Measurements were serial and separate from full tests/builds. Relative to baseline legacy these policies have materially lower throughput (about 63–66% lower) and longer latencies for this tiny sequential workload. Raw socket handlers avoid the action/receipt coordination costs. New policies perform bounded action/Writer/outcome handling rather than a direct raw-socket call; per-datagram initializes and terminates each invocation, endpoint/keyed retain application state. Those costs are part of their measured behavior, not implied improvements over legacy execution.

## Controlled overload and lifecycle

`devenv shell -- bash -c 'cd .trees/udp-runtime && mix run scripts/udp/runtime_stress.exs'` passes actual traffic, blocked callback/Writer and observed process DOWN gates for all three policies, five epochs each (`p6-runtime-stress-stop-final.log`). Offered UDP load is 1320 packets per policy in batches with explicit receive barriers; admitted 40, application drops 1280. Direct egress offers 180, rejects 160, verifies 60 actual replies across the five epochs. Kernel drops are unmeasured.

| Observed/accounted bound | Result | Configured ceiling |
|---|---:|---:|
| Input items | 8 | 8 |
| Retained input bytes | 7,160 | 16,384 |
| Egress entries | 4 | 4 |
| Egress bytes | 2,048 | 4,096 |
| Baseline/final process count | 116/116 | Sample only |
| Sampled process high:per_datagram/endpoint/keyed | 134/127/130 | Sample only |
| Owner mailbox high | 1 | Sample only |
| Runtime mailbox high | 3 | Sample only |
| Writer mailbox high | 3 | Sample only |

Counters cover queued and in-flight host-managed work, including helper/worker ownership. Protected input quota stays reserved until the actual helper/worker monitor DOWN; component death cleans Writer/Admission even with no input. Samples alone do not prove native resource reclamation or quantify arbitrary application-state memory. Tests use explicit admission/receipt/monitor barriers; sleeps and snapshots are not reclamation proof.

The unchanged legacy stress workload has matching baseline/final results (`baseline-stress.log`, `p6-legacy-stress.log`):processes 115→high 123→final115, active high 2, owner mailbox high 1, retained high 996 bytes. This is scoped overload evidence, not a claim that new application state or the whole VM is bounded to that size.

These latest measurements cover the completed-effects and absolute-stop repairs, source manifest `8736649a89a4e33cb448ec79cd1473d1015a922a1c431f8d73c73e48fe749a66`. All 15 serial samples PASS; `p6-performance-stop-final.log` records run output. Earlier samples are retained with `pre-effects-fix-` and `pre-stop-fix-` filenames and source-attributed JSON references; their 6.5% and 3.9% legacy regressions are historical. Differences between snapshots are not proof of causal improvement.
