# Abyss DHCP socket (unpublished optional package)

This independent OTP package owns the Rustler build and native artifact for interface-bound DHCP client UDP and raw ARP. It does not depend on Abyss or start a socket/poll thread at application startup. `AbyssDhcpSocket.Native` implements the five native operations; existing callers use the pure Elixir `Abyss.DhcpSocket.Native` facade supplied by Abyss.

DHCP users must explicitly install this package when upgrading Abyss. This package is currently unpublished; the provisional package name/version is not an available Hex dependency. For a local opt-in development fixture only, add `{:abyss_dhcp_socket, path: "packages/abyss_dhcp_socket"}` with the path adjusted relative to your consumer. No local path is declared by the production core package.

Build with Elixir/Mix and Cargo/Rust. The crate and Cargo.lock are preserved from Abyss. Its shared library belongs to `:abyss_dhcp_socket` under `priv/native/dhcp_socket`, never the core application. The package does not ship `Abyss.DhcpSocket.Native` or require a dependency cycle.

`open(interface, owner)` returns an opaque resource directly or `{:error, reason}`. Sends return `:ok` or `{:error, reason}`; `close/1` is idempotent. DHCP binds UDP port 68 and sends to port 67. Linux raw ARP needs `CAP_NET_RAW`; binding low ports may need `CAP_NET_BIND_SERVICE`. macOS/FreeBSD raw ARP remains unavailable, as before. Existing owner messages and the shutdown behavior are unchanged. Owner death is observed when packet delivery fails; resource cleanup or explicit `close/1` closes the descriptors. Do not infer immediate native reclamation from process death.

Run independent validation:

```sh
cd packages/abyss_dhcp_socket
mix deps.get
mix test
bash scripts/test_arp.sh
cargo clippy --manifest-path native/dhcp_socket/Cargo.toml --locked --all-targets -- -D warnings
```

The ARP script runs the five existing source unit tests in a disposable Rust-only harness without linking BEAM NIF symbols. Native DHCP/ARP wire validation uses `scripts/udp/dhcp_fixture.py` through `python3 scripts/udp/p5_consumers.py` from the repository root. It shares the existing UDP namespace topology, confines capabilities and packets to those namespaces, and never changes the ambient LAN. This validation is opt-in and requires namespace setup permission. No publication is performed.
