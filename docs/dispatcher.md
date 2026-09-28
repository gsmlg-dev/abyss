# Opt-in datagram dispatcher and writer

Default Abyss UDP mode creates a legacy handler per datagram. Persistent UDP
protocols can configure `datagram_dispatcher: Module` or `{Module, options}` on
a unicast listener; the module implements `Abyss.DatagramDispatcher`. QUIC
applications instead use the supported [QUIC service](quic-service.md), which
owns application binding and uses the same independent writer. The lower-level
`QUIC.AbyssDispatcher` adapter alone is not an application service.

The dispatcher runs separately from the listener's blocking `recv(:infinity)`.
Callbacks can register generic routes via `{:new, keys, pid, state}` or
`{:route, keys, pid, state}`. Replacing routes removes displaced monitors;
process death removes only that process's routes. QUIC services do not install
a second CID registry here: `QUIC.Endpoint` remains authoritative.

## Writer capability and outcomes

The callback context provides `send`, a generation-scoped
`Abyss.Dispatcher.SendCapability`, and `send_fun.(remote, binary)`, which waits
for local completion. A capability authorizes only this listener's writer.
Neither a callback nor a connection may close the shared socket.

- `Abyss.Dispatcher.send(capability, remote, bytes, timeout)` reserves both one
  item and its bytes, then atomically hands the payload to the writer through
  an independent admission process. `{:ok, send_ref}` means admission only.
- `Writer.await(writer, capability, send_ref, timeout)` returns
  `{:ok, completed_at}` after the socket send, in monotonic microseconds, or a
  transport error. `send_receipt/4` composes admission and this wait.
- A submitted-call or receipt timeout returns `{:unknown, send_ref}`. It is not
  cancellation; do not blindly retry. The capability retains the generation.
- Reservation timeout returns `{:error, :writer_timeout}` before any payload
  submission, and sends an ordered cancellation of the control-only reservation.
- Unknown/expired references return `{:error, :unknown_send}`; a stale generation
  returns `{:error, :stale_generation}`. Writer/gate death rejects admission.

Credits include queued **and in-flight** work, including payloads awaiting writer
mailbox processing. They are released exactly once by completion, unused
reservation cancellation/death, or writer teardown. A caller dying after payload
handoff does not free credit prematurely. The writer performs socket sends itself,
with no task per packet and no synchronous listener call.

The independent gate remains responsive while the writer is blocked. At most one
waiter per reference is admitted; another receives `:already_awaiting`. Waiters
have deadlines and process monitors and are removed on timeout/death/completion.
Results have a finite count (default 256) and lifetime (default 5 seconds),
including idle expiration. Eviction/expiration makes the outcome unresolvable;
it never proves the datagram was not sent. These are local socket receipts, not
peer ACKs. The host receives generation-tagged completion notifications.

A QUIC external sender must return completion, not a reference. The service
converts an unknown writer outcome into an explicit error with the generation
and reference; ex_quic terminates the uncertain connection without reusing packet
numbers. No automatic retry is added by Abyss.

## Failure ownership

Writer/admission death makes the dispatcher fail closed and invokes callback
cleanup. Callback initialization failure reaps its writer even if transport send
is blocked. The admission companion observes owner death and kills a blocked
writer; writer death resolves waiters, invalidates its lookup and stops the gate.
The owning QUIC service drains its workers within a configured deadline and then
terminates its host components and closes its socket. One connection close never
closes that socket. Stale or late completion cannot refund a different generation.

The dispatcher remains unavailable in broadcast mode and optional. Omitted
QUIC/dispatcher configuration does not load or require ex_quic. Callers must use
the capability API rather than forging internal GenServer messages. Application
code is responsible for its own bounded input queues; this contract bounds
admitted writer payloads, not arbitrary messages sent by hostile local processes.
