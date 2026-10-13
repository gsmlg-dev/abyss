# P5 optional DHCP/ARP package extraction

Status: **PASS (G6 on Linux OTP 27 and OTP 28)**. Baseline `9b710e6480900e16e304f40e63623aff8c922e19`, worktree `.trees/udp-runtime`, branch `codex/udp-runtime`. The optional package remains unpublished and uses a provisional name/version. No commit, push, dependency upgrade, sibling edit, or publication was performed.

## Package and migration

`packages/abyss_dhcp_socket` is an independent Mix/OTP package, not an umbrella child. It owns Rustler, `AbyssDhcpSocket.Native`, the native crate, native artifact under its own OTP application, independent Mix lockfile, tests and copied MIT license. It does not depend on Abyss or start native sockets at application startup.

The root retains `Abyss.DhcpSocket.Native` as a pure Elixir facade. All five function names/arities delegate lazily when selected. Missing installation returns `{:error, {:missing_optional_dependency, :abyss_dhcp_socket}}`; loading failures return an explicit optional-dependency error. Ordinary UDP does not load the implementation or require privileges. Root no longer declares Rustler or packages native source/artifacts.

DHCP users must explicitly install the optional package. It is currently unpublished; no available Hex version is asserted. Local opt-in fixture consumers can use the repository package via a relative path. The production root dependency list has no unpublished path or version dependency. See `packages/abyss_dhcp_socket/README.md` for build/test commands and migration guidance.

`open/2` retains its actual opaque-resource return (the old tuple spec was inaccurate). Sends retain `:ok`/`{:error, reason}`, native argument validation, and idempotent close. Existing DHCP/ARP owner messages are unchanged. The native code was preserved byte for byte except `rustler::init!` changing the implementation namespace. Cargo.lock, Cargo.toml, .cargo config and LICENSE remain intact; see `evidence/p5-source-integrity.log`.

## Acceptance evidence

Before root removal, `python3 scripts/udp/p5_consumers.py --staged` built candidate Hex archives outside the checkout and passed both consumers (`p5-staged-consumers-otp27.log`, temporary stage `/tmp/abyss-p5-2airf_1v`). Only then was the tracked root crate removed and the facade/Mix extraction applied.

After extraction, `python3 scripts/udp/p5_consumers.py` passed independently on both runtimes:

- OTP 27 through `devenv shell -- bash -c 'cd .trees/udp-runtime && python3 scripts/udp/p5_consumers.py'`: `p5-final-consumers-otp27.log`, `/tmp/abyss-p5-lj38kxrk`.
- OTP 28 through `ERL_FLAGS='+S 8:8' python3 scripts/udp/p5_consumers.py`: `p5-final-consumers-otp28.log`, `/tmp/abyss-p5-kvalxiyd`.

Each consumer installs source extracted from actual Hex `contents.tar.gz`, with separate fresh dependency/build directories and no copied native/build cache. Core resolves/builds/boots with Cargo/Rust/rustup absent from PATH (also checked inside BEAM), checks dependency/application/module absence, has no packaged native directory or binary artifacts, verifies all five missing-package facade calls, and completes an actual loopback Abyss endpoint UDP exchange. Development-only consumer path dependencies reference extracted archives, not the worktree.

Optional consumers explicitly add the extracted package, compile/load the NIF, and exercise the retained core facade. `dhcp_fixture.py` imports the existing `network_fixture.Fixture`, uses its four disposable namespaces/two isolated networks, drops to the invoking uid, and retains only `CAP_NET_RAW`/`CAP_NET_BIND_SERVICE` inside fixture namespaces. Both runtime runs passed 11 checks: port-68 bind, independently received broadcast/unicast with exact source address/port, DHCP owner payload, RFC5227 probe frame, full ARP owner frame, idempotent close, closed-send errors, independently observed kernel bind release, dead owner plus explicit close, and orphan bind release. Teardown joins/close is the completion barrier; no sleep proves native reclamation.

Independent package `mix test`: **3 tests, 0 failures** on each runtime (`p5-package-tests-otp27.log`, `p5-package-tests-otp28.log`). `bash packages/abyss_dhcp_socket/scripts/test_arp.sh`: **5 existing ARP source tests, 0 failures**, in a disposable Rust-only harness (`p5-arp-tests.log`). Locked `cargo clippy --all-targets -- -D warnings`: **PASS** (`p5-clippy.log`). Scoped format, Python syntax, shell syntax, source integrity and `git diff --check`: **PASS**. Scoped strict Credo checked five P5 Elixir files with no issues (`p5-credo-scoped.log`). An initial invalid Credo switch and an accidentally broad scan are retained in separate logs; unrelated baseline issues were not changed.

## Limits and handoff

No macOS/FreeBSD native execution was available in this Linux phase. Existing non-Linux ARP/BPF restrictions remain unchanged. Fault injection for native `poll_error`/`recv_error`/`socket_error` messages was not performed; their source and formats are preserved. The dead-owner check explicitly closes a retained resource and does not claim process `DOWN` alone reclaims native descriptors or immediately retires the poll thread. Pre-existing ignored root build artifacts were not used by the fresh packaged gates.

Root owner handles README/public migration integration and workflow cache paths: the old `native/dhcp_socket/Cargo.lock` cache key should become the optional-package path when a workflow opts into native validation. Full regression, minimum-runtime/macOS checks, release and QUIC consumer integration belong to P6/root.
