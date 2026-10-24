# Coordinated Abyss releases

`abyss` and `abyss_raw` always share a release version, tag and GitHub Release.
Publish both packages even when a change affects only one. The root manifest's
`@version` is authoritative; the standalone raw manifest carries the same
literal value so an extracted Hex archive builds without its parent checkout.
`scripts/release/release.py check --version V` rejects divergent versions or an unexpected
distributable package. Examples are not release packages.

Core has no dependency on `abyss_raw` or Rustler and uses no Cargo build.
Applications opt into `abyss_raw` explicitly. The raw package builds independently
and has no dependency on core. Its implementation keeps the compatibility name
`AbyssDhcpSocket.Native` and the crate name `dhcp_socket`; its native library belongs
to the `:abyss_raw` application's `priv` directory. `Abyss.Transport.UDP.Native`
remains the separate OTP `:socket` backend in core.

## Prepare the source

Choose an unused version after checking Hex and repository tags. Update both
manifests, installation examples and release notes, then validate before committing:

```sh
python3 scripts/release/release.py check --version 0.10.0
python3 -m unittest discover -s scripts/release -p 'test_*.py'
mix format --check-formatted
mix test --no-cover test/abyss/dhcp_socket_native_test.exs
mix docs --warnings-as-errors
python3 scripts/udp/p5_consumers.py
```

The consumer gate builds both archives and extracts them outside the checkout.
It hides Cargo/Rust for a fresh core consumer, checks a UDP round trip, builds
the raw package independently, checks current and released 0.8.1 facade
compatibility, and verifies an explicitly selected native Mix release. The Linux
DHCP/ARP wire gate uses the existing isolated namespace fixture and requires
passwordless namespace setup privilege. `--no-wire` runs the unprivileged subset
and reports wire checks as NOT RUN; it is not a substitute for the release gate.
See [fixture prerequisites](../scripts/udp/README.md).

Commit and push the accepted source, including both version changes, before
dispatch. Do not edit versions inside a release runner. From the repository's
GitHub Actions **release** workflow, select the branch containing the coordinated
workflow and supply:

- `release-version`: the committed common version, for example `0.10.0`.
- `git-ref`: the exact source commit, or a ref resolving to that commit.

CLI dispatch accepts an exact source commit independently of the workflow ref:

```sh
gh workflow run release.yml --ref main \
  -f release-version=0.10.0 -f git-ref=<validated-commit>
```

The workflow validates the selected checkout, builds every package from that
commit, and uses the existing bare version tag convention (`0.10.0`). It rejects
an existing tag that points elsewhere. Only manual dispatch starts publication;
one repository-wide concurrency group serializes releases without canceling
an upload in progress. The workflow needs the repository's existing `HEX_API_KEY`
secret with permissions to publish both packages and their docs.

## Artifacts and publication

The single GitHub Release contains `abyss-V.tar`, `abyss_raw-V.tar`, `SHA256SUMS`
and a manifest identifying the validated source. It first records publication as
incomplete, then uploads core and raw to Hex separately from their respective
package roots, publishes both documentation sets, and runs fresh exact-version
Hex consumers. Both package artifacts and consumers must verify before the
release status becomes complete. A successful upload of only one package is
an incomplete coordinated release.

The final verification fetches each registry checksum and official archive,
compares the archive bytes to the GitHub artifacts, and checks the downloaded
consumer source. Consumers use exact Hex dependencies, never Git or local paths
for the final publication check. Native artifacts are built on the target
platform; the source Hex archive contains the locked Rust crate, while an
explicit native Mix release includes its compiled library.

## Resume an incomplete publication

Preserve the common tag and any successfully published package. Rerun with the
same source commit and version. The release helper verifies the existing GitHub
assets against that source, checks existing Hex archives against those assets,
and uploads only missing packages. It tracks package upload, docs and verification
separately in the release status. Missing docs can be published on retry without
replacing an existing package archive.

If an existing tag, artifact or Hex package conflicts, stop and diagnose the
conflict. Never move the tag or overwrite published package contents. If recovery
requires new source, advance **both** package versions and create a new common
release. Do not migrate downstream consumers until both Hex packages are verified.
