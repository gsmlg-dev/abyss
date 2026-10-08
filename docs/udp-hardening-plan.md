# UDP hardening plan

Baseline: `main`, `671d0d7f004c56e4b170402f074547eed2731d04`; the supplied implementation prompt was the only untracked file. No source downgrade, dependency edits, sibling edits, publishing or host LAN traffic is authorized.

## Baseline findings and reproductions

| Finding | Reproduction status and evidence | Final response |
| --- | --- | --- |
| U1 | Reproduced: housekeeping prevents expiry; infinity adaptive arithmetic raises. `udp-evidence/accounting-baseline-red.log` contains labeled original transcript extracts. A later early-current-token event regression also failed (`accounting-early-timer-red.log`). | Explicit monotonic deadline, tagged timers, stale-event rejection and early-event rearming; housekeeping does not reset expiry. |
| U2 | Reproduced API/accounting defect: rejection returns success; source confirms per-rejection sleeping Tasks. Original red extracts are in `accounting-baseline-red.log`. Baseline process-growth stress was NOT RUN; no baseline high-water figure is invented. | Drop new work; serialize server-wide reservations and cleanup; fixed starter per receive owner, no retries/pending payload queue. |
| U3 | Source-confirmed socket closure on suspend. Initial host regressions failed before the pause assertion because port zero created four sockets (`host-red.log`); the delayed-reply pause/drain assertions were not independently reached on baseline. | Keep socket open through suspension and admitted-handler drain; one overall shutdown deadline. Final host tests exercise real delayed replies. |
| U4 | Reproduced false response count on handler termination and missing endpoint accounting APIs (`accounting-baseline-red.log`). Pre-start acceptance/module scope also confirmed in source. | Logical-server scope, successful validated admission, actual transport-send outcomes, monitored lease cleanup. |
| U5 | Source-confirmed incorrect byte multiplication; baseline regression lacked the byte-unit helper (`accounting-baseline-red.log`), so it was not a direct baseline arithmetic assertion. | Sample process memory in bytes; independently assert the conversion and document sampling limitations. |
| B1 | Source-confirmed forced active reception and unhandled ancillary tuple. Baseline ancillary packet delivery regression was NOT RUN independently. | One active credit, socket/generation validation, real ancillary metadata through handlers/dispatcher. Final actual tuple tests and wire fixture pass. |
| M1 | Reproduced all four normalization failures: memberships, raw tuple, family/mode aliases, invalid port (`transport-client-red.log`). Later host ordering failure is retained in `membership-order-red.log`. | Preserve operations/raw forms; validate all startup operands, reduce host add/drop in original order and restore final desired set. |
| M2 | Missing facade/IPv6 contract reproduced (`transport-client-red.log`). Real fixture exposed OTP IPv6 startup membership collapse and wrong IPv6 hop/loop values (`ipv6-membership-red.log`, `ipv6-options-red.log`, `network-ipv6-hop-fail.log`). | Explicit group/family/interface/scope APIs; individually apply memberships, tested Linux kernel option mappings and explicit unsupported-capability errors. |
| C1 | Reproduced silent interface fallback, ignored oversized send, invalid deadline acceptance and missing collection readiness (`transport-client-red.log`). Baseline resource-growth/receive-error test was NOT RUN independently. | Shared validated settings, checked sends, bounded count/bytes/absolute deadline, partial/error outcomes, guaranteed temporary-socket cleanup. |
| T1 | Confirmed unconditional network-success branches in baseline test source; this is a test-quality finding, not a failing network assertion. | Replace affected branches with actual exchanges; mandatory independent Linux fixture fails on missing setup or packets. |

No finding was classified as already fixed at the actual baseline. The two original red summary files explicitly identify transcript extracts rather than pretending to preserve full raw logs. Final raw green logs and fresh final acceptance are separate evidence.

The first host regression run failed 5/5: port zero created four unrelated ephemeral sockets before any lifecycle assertion could execute (`udp-evidence/host-red.log`). Baseline existing listener/pool/server/config tests passed 58 assertions; scoped coverage alias failed its unrelated whole-project threshold, so focused runs disable coverage.

## Design and invariants

1. Tagged monotonic idle timers survive housekeeping; only application progress resets idle expiry. Memory sampling measures bytes and is advisory: blocked callbacks and shared binaries prevent a strict total-memory guarantee.
2. Drop-new admission: zero pending items, zero pending bytes and no pending age/retries. Each receive owner grants exactly one active-once credit. One fixed linked starter per socket isolates custom startup. At most one start reservation retains one complete payload, bounded by max_packet_size and an absolute admission_start_timeout. Expiry releases that payload and counts its drop once, but retains an empty busy reservation until startup resolves; a late handler is killed before delivery. This avoids generating another startup queue behind a stalled callback.
3. Successful startup is not admission until the owner validates its token, running generation and deadline. Active plus reserved handlers stay within the server-wide num_connections ceiling, including multiple fixed-port unicast listeners. The reservation ledger serializes transitions through TableOwner, including owner-death cleanup, avoiding split ETS update races. Monitored death releases accounting even after kill. Empty datagrams consume one item.
4. Pausing retains sockets and desired memberships, discards new received datagrams, and permits existing handlers to reply. Resume reuses the endpoint. One logical ephemeral/broadcast/multicast endpoint has one receiving socket. Dynamic scaling is rejected for these modes.
5. Drain rejects new work, lets admitted datagrams complete their local sends, and closes I/O after completion or one absolute deadline. Dispatcher/QUIC cleanup is explicitly narrower than graceful application-session completion.
6. UDP option normalization preserves memberships/raw options/order. Host startup reduces validated add/drop operations into the final desired set; direct Core transport operations retain OS operation order. Membership joins/leaves run in the owner using the configured transport, with idempotent desired-set changes and generation restoration. Peer and ancillary metadata are real received values; wildcard binding is not packet destination metadata.
7. Client collectors have count, byte and absolute deadline ceilings and propagate send/receive errors with partial results.

The bounds cover library-generated network work and supported operations. Hostile local senders injecting arbitrary mailbox messages are outside this guarantee. UDP credits bound local retention; they cannot backpressure arbitrary network senders. Only explicit library drops are counted; kernel drops are separate.

## Implementation and acceptance order

Baseline/reproductions → timers and admission → socket ownership/pause/drain → options → broadcast/multicast/client → telemetry compatibility → isolated independent network/stress and current QUIC consumer → CI/public docs/acceptance.

Implementation is complete in the uncommitted checkout. See `udp-hardening-acceptance.md` for the final gates, source manifest, commands, measured bounds, platform restrictions and unrun environments. No package dependency or lockfile change is required; the DHCP NIF and optional QUIC boundary are preserved.
