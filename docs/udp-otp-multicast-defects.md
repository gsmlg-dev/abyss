# OTP multicast option reproductions

Observed on Linux with Elixir 1.18.5 / OTP 28.5.0.5 (`inet` backend), and the
socket backend checked on OTP 28 and OTP 27 / Elixir 1.18.4. This records
upstream behavior without modifying OTP or any sibling repository.

## IPv6 startup membership collapse

```elixir
{:ok, socket} = :gen_udp.open(0, [
  :inet6, {:active, false},
  {:add_membership, {{0xFF02, 0, 0, 0, 0, 0, 0, 0xAA74}, 1}},
  {:add_membership, {{0xFF02, 0, 0, 0, 0, 0, 0, 0xAA75}, 1}}
])
IO.puts(File.read!("/proc/net/igmp6"))
:gen_udp.close(socket)
```

Only the second group is present on `lo`. OTP's `inet:udp_opt` has a special
IPv4 membership branch; IPv6 reaches `add_opt`, which deletes the previous
option with the same key. An independent fixture's first IPv6 group timed out.
`Abyss.Transport.UDP.Core` retains every normalized membership and applies each
separately using public `:inet.setopts` after opening, with socket-close rollback.
The regression asserts both actual OS entries. A successful leave is insufficient
as proof: native `:inet.setopts` also returned `:ok` for a nonexistent IPv6 leave.

Evidence: `udp-evidence/ipv6-membership-red.log`,
`udp-evidence/ipv6-membership-green.log`, and isolated network artifacts.

## Generic options target IPv4 controls on IPv6 sockets

```elixir
{:ok, socket} = :gen_udp.open(0, [
  :inet6, {:active, false}, {:multicast_ttl, 5}, {:multicast_loop, false}
])
IO.inspect(:inet.getopts(socket, [
  :multicast_ttl, :multicast_loop,
  {:raw, 41, 18, 4}, {:raw, 41, 19, 4}
]))
:gen_udp.close(socket)
```

Generic getters report `5` and `false`; the actual IPv6 hop/loop controls are
both `1`. Subsequent generic setters change only the generic IPv4 values. The
isolated Python peer received hop limit `1` after a requested `5`.

For an existing positive interface index `1` on `lo`:

```elixir
{:ok, socket} = :gen_udp.open(0, [:inet6, {:multicast_if, 1}])
IO.inspect(:inet.getopts(socket, [:multicast_if, {:raw, 41, 17, 4}]))
:gen_udp.close(socket)
```

The IPv6 egress option remains `0`; the generic getter can return an unrelated
negative value. With `inet_backend: :socket`, opening with that generic index
returned `{:error, :einval}`. Explicit sockaddr scope can mask the missing
egress setting, so send success alone does not validate this option.

Abyss uses the public raw UDP socket options for the tested Linux IPv6 ABI,
converts runtime setters/getters, and checks actual raw kernel values on both
backends. Non-Linux IPv6 multicast controls return an unsupported-capability
error until the platform ABI is tested. No runtime minimum is raised silently.

Evidence: `udp-evidence/ipv6-options-red.log`,
`udp-evidence/ipv6-options-green.log`, and the retained
`udp-evidence/network-ipv6-hop-fail.log`.

## Unknown raw options may be ignored by the native inet backend

```elixir
{:ok, socket} = :gen_udp.open(0, [{:raw, 65_535, 65_535, <<0::native-32>>}])
:gen_udp.close(socket)
```

This invalid level/option returned a live socket. Abyss validates raw option
forms and preserves ordering; it cannot claim that native OTP reports every
kernel raw-option failure. Documented supported IPv6 mappings are independently
validated against real kernel values and traffic. This limitation remains
explicit for callers supplying arbitrary raw options.


## OTP 27 socket backend rejects named IPv4 multicast controls

On OTP 27 / ERTS 15.2.7.4 / Elixir 1.18.4, each of these options independently
makes `:gen_udp.open(0, [{:inet_backend, :socket}, {:active, false}, option])`
return `{:error, :einval}`:

```elixir
{:multicast_if, {127, 0, 0, 1}}
{:multicast_ttl, 1}
{:multicast_loop, true}
```

The corresponding named getters return `{:ok, []}`. Linux public raw controls
work: IPPROTO_IP level 0, option 32 with four IPv4 bytes, option 33 with a native
32-bit TTL, and option 34 with a native 32-bit loop boolean. Abyss maps these
controls for socket-backend open and runtime operations and restores the
public getter shapes. Independent raw kernel values and real multicast receipt
prove the settings; native `inet` IPv4 controls remain unchanged.

Evidence: `udp-evidence/otp27-option-isolation.log`,
`udp-evidence/otp27-raw-multicast-wire.log`,
`udp-evidence/otp27-linux-final.log`, and `udp-evidence/network-socket-green.log`.

## Socket-backend membership tuple setters

OTP's `gen_udp_socket` membership option conversion rejects generic IPv4/IPv6
membership tuples. Abyss uses public raw socket controls on Linux only:
IPPROTO_IP 0 add/drop 35/36 with an `ip_mreqn`, and IPPROTO_IPV6 41 add/drop
20/21 with an `ipv6_mreq`. Regression tests check actual receipt and Linux
membership tables. A partial startup adds a unique IPv6 group, then drops a
nonjoined group; socket backend returns `:eaddrnotavail`. Abyss closes the
socket and the test confirms no group, port, or socket remains. Native `inet`
can suppress the same nonexistent-leave error, so a generic setter return
cannot prove complete OS validation.

## Socket backend rejects scoped sockaddr map sends

This public OTP send reproduces an `exit :badarg` on Linux OTP 28; the OTP 27
socket implementation also lacks a sockaddr map clause in `dest2sockaddr`:

```elixir
{:ok, socket} = :gen_udp.open(0, [{:inet_backend, :socket}, :inet6, {:active, false}])
try do
  :gen_udp.send(socket,
    %{family: :inet6, addr: {0, 0, 0, 0, 0, 0, 0, 1}, port: 49000, scope_id: 1},
    "scoped")
after
  :gen_udp.close(socket)
end
```

Abyss returns `{:error, {:unsupported_capability, :scoped_sockaddr_send, :socket}}`
for this capability instead of crashing or discarding the scope. The client
rejects it before opening its temporary socket. Native `inet` retains the full
scoped IPv6 multicast path, verified in isolated network namespaces. The socket
fixture reports only the supported IPv4 matrix as `PASS_SUPPORTED_SUBSET` and
explicitly identifies `ipv6_scoped_wire` as unsupported.

Evidence: `udp-evidence/network-socket.log` (original failure),
`udp-evidence/socket-controls-red.log`, `udp-evidence/socket-controls-green.log`,
and `udp-evidence/network-socket-green.log`.
