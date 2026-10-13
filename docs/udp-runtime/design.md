# UDP datagram runtime contract

`Abyss.Endpoint` delegates startup and control to the existing Abyss supervision tree. `Abyss.Listener` remains the only socket owner and membership authority. New endpoints select `datagram_handler: Module`; simultaneous legacy handler/dispatcher selection is rejected. One physical receiver is required for this initial new API. Legacy raw-socket handlers and dispatcher receipt APIs remain separate and compatible.

`Abyss.Datagram` fields use `nil` for unavailable values. `peer` is a sockaddr map including family/address/port and observed IPv6 scope when available. `local_endpoint` is the bound address/port and preserves wildcard binds. Destination, ingress interface, local unicast address and hop limit come only from real receive controls. `received_at` is BEAM monotonic microseconds at receive processing, not kernel arrival. Ancillary controls and flags are bounded by adapter buffers and input quotas. Telemetry sampling never changes the value.

`Abyss.DatagramHandler` callbacks:

- `init(options, context) -> {:ok, application_state} | {:error, reason}`. Context includes endpoint ID, socket generation and immutable send capability; no raw socket.
- `handle_datagram(datagram, state) -> {:ok, state, actions} | {:stop, reason, state, actions} | {:error, reason, state}`.
- Optional `handle_event({:timer, token, value}, state)` uses the same transition contract.
- Optional `terminate(reason, state)` receives the last returned application state, including invalid-action and stop/error paths; forced callback death cannot recover an unreturned state.

Finite actions: `{:reply, binary}`, `{:reply, binary, :strict}`, `{:send, sockaddr, binary}`, `{:timer, token, delay_ms, value}`, `{:cancel_timer, token}`. Stop is explicit in the transition. Action count and total payload bytes are validated before any effects; submissions are individually reported and are not atomic. Routing-based reply is default. Strict reply requires actual source/interface metadata and verified per-message controls from the original socket, otherwise rejection is explicit.

Policies: `:per_datagram` has one init/invocation/cleanup; `:endpoint` retains one serialized application state; `:keyed` requires an explicit route function or `{module, function}`. The key is opaque, bounded by serialized size, with finite key count and idle expiry. Routing is serial in local admission order outside socket/control processes, and watchdog bounded. Different active keys execute concurrently; no invocation is retried after failure. Idle expiry only advances on application work, not inspection or stale timers.

Global input item credit reuses UDPAdmission. Bytes count queued, routing, initializing and executing work. Persistent queues have item/byte quotas; timer events use the same credit and a finite timer count. Full admission drops new work. No task is allocated per rejected packet. Callback/startup/route/cleanup watchdogs are owned by a separate runtime coordinator. Defaults and exact option names are documented in migration.md.

Egress reuses Dispatcher.Writer/Admission and its generation-scoped receipts. `Endpoint.send` returns `{:ok, ref}` for admitted work, not delivery. `Endpoint.await` returns local completion `{:ok, monotonic_microseconds}`, definite failure `{:error, reason}`, or `{:unknown, ref}`. References remain resolvable for finite retention; timeout is not cancellation. Per-datagram action outcomes are retained by the endpoint, including after worker exit. Stale-generation capabilities cannot submit to replacement writers.

Pause is an admission barrier retaining socket and accepted effects. Drain uses the original absolute deadline for input work and writer entries; expiry forces cleanup and local outcomes may remain unknown. Memberships restore through existing TableOwner storage on listener restart. Old worker/timer/receipt capabilities do not operate on a replacement generation; ephemeral ports may change.

`io_backend: :gen_udp` uses effective `inet_backend: :inet | :socket` separately. `io_backend: :socket_native` uses direct public OTP socket APIs and Linux control encodings, never a GenUDP descriptor. Native/legacy combinations and contradictory selectors are rejected. Capabilities distinguish supported, enabled, and unavailable reason; availability is never inferred from a configured group or a successful setter alone.

Internally, the seven new flat startup options are normalized into `ServerConfig.datagram_options`. All legacy struct fields stay intact. This keeps backend/policy/requirements together without changing the public keyword startup syntax or expanding the legacy configuration into unrelated fields. The existing TableOwner monitors active input roots/helpers and endpoint Writer/Admission components; forced retirement refunds input quota only after actual protected descendant DOWN. Normal callback turns explicitly acknowledge detachment before live persistent workers can release their current input.

New flat option duplicates consistently use the first keyword occurrence for validation, backend selection and normalized storage. Legacy and raw socket option ordering/precedence remain unchanged. Required new egress item/byte quotas are finite positive integers even without a legacy dispatcher.

Completed effects retire their watchdog only after the terminal result and actual normal helper DOWN. An already-queued expiry then cannot kill the application worker. Input credit remains reserved until the library-owned worker settlement/worker DOWN; accepted egress remains reserved until its terminal Writer accounting. Unfinished effects retain their configured deadlines, and endpoint stop retains its absolute deadline.
