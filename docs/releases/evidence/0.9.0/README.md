# Abyss 0.9.0 publication evidence

Both Hex packages are verified and downstream migrations may proceed.

- Shared version and immutable common tag: `0.9.0`.
- Validated source: `f336d939ff8a23b38c66072f1d1ba5873b5ef43b`.
- [GitHub Release](https://github.com/gsmlg-dev/abyss/releases/tag/0.9.0).
- [abyss on Hex](https://hex.pm/packages/abyss/0.9.0) and
  [abyss_raw on Hex](https://hex.pm/packages/abyss_raw/0.9.0).
- [Coordinated release workflow](https://github.com/gsmlg-dev/abyss/actions/runs/39534666626):
  successful, with both uploads, documentation sets and verifications complete.

| Archive | SHA-256 |
| --- | --- |
| `abyss-0.9.0.tar` | `d13364b95d070abce970c5e7633e49648f9fc9157a7ca5f4d88464454b6d7a48` |
| `abyss_raw-0.9.0.tar` | `6fea2ac8089c09a0ab58fbc96031b29badd83d50486c9ee3b29eb15a2a567c9d` |

The downloaded Hex archives are byte-identical to the intended release assets;
their hashes match both GitHub asset digests and the Hex registry. All 47 core
and 11 raw packaged files match the immutable source and the completion
worktree. Both documentation sites returned HTTP 200. The final evidence-only
changes are outside both package file selections, so advancing `main` does not
change the tagged or published packages.

[published-verification.json](published-verification.json) is the final receipt.
[manifest.json](manifest.json), [SHA256SUMS](SHA256SUMS) and
[github-release.json](github-release.json) retain artifact and publication
identity. [workflows.json](workflows.json) records source-specific job outcomes,
including both main Test attempts.

[published-workflow-consumers.json](published-workflow-consumers.json) and
[published-consumers.json](published-consumers.json) each record six successful
fresh-consumer gates: independent extracted raw build; core UDP without Rust;
combined native load and operation errors; explicit native Mix release
artifact; released core 0.8.1 facade; and isolated DHCP/ARP with cleanup.
The published core and combined consumers use exact-version Hex dependencies.
[published-native-wire.json](published-native-wire.json) retains all 11 isolated
native assertions. [workflow-archive-consumers.json](workflow-archive-consumers.json)
records the workflow's prepublication archive checks;
[local-consumers.json](local-consumers.json) is the earlier local candidate run.
Candidate archive hashes are not publication receipts.

To repeat published verification after downloading all GitHub release assets:

```sh
python3 scripts/release/verify_consumers.py --version 0.9.0 \
  --artifacts /path/to/downloaded/assets --published --legacy --wire \
  --output /tmp/abyss-0.9.0-verify.json
```

The wire gate requires a Linux host with the supported isolated-network fixture
tools and permissions. No new FreeBSD or other native-platform verification is
claimed.

The release core suite passed 691 tests and 3 doctests, with 7 excluded; raw
package tests passed 3/3 and release-helper recovery tests passed 20/20. Main UDP
regressions passed 3/3 jobs (Linux OTP 27/28 and macOS OTP 28); the isolated
network matrix passed 19/19. Local Rust ARP, Clippy, strict documentation,
formatting and compatibility acceptance are recorded in the
[completed checkpoint](../../0.9.0-progress.md).

Main Test attempt 1 failed the existing dispatcher's 100 ms EXIT assertion at
`test/abyss/dispatcher_test.exs:298`, seed `665934`, max cases 8; the mailbox was
empty. [main-test-attempt-1.log](main-test-attempt-1.log) preserves the failure.
The implementation, dispatcher test, root lockfile and Test workflow are
byte-identical to baseline `98fc278`. Scoped runs on
[current](dispatcher-current-scoped.log) and
[baseline](dispatcher-baseline-scoped.log) both passed (19 tests, 18 excluded).
The unchanged remote retry passed 691 tests and 3 doctests, with 7 excluded;
see [main-test-success.log](main-test-success.log). The precise scheduling cause
was not established.

The separate main CI workflow remains failed: strict Credo reports 83 findings
in 21 unchanged files (15 warnings, 15 refactoring, 48 readability, 5 design),
and Dialyzer reports `Old PLT file .../priv/plts/dialyzer.plt`. Compilation and
formatting jobs passed. [main-ci-failed.log](main-ci-failed.log) retains these
failures; no unrelated CI/cache or code-quality repair is included.

The independent verifier's initial invocation preceded artifact download and
failed during setup with a missing local archive. The corrected invocation
produced the successful published receipt above; its logs and the initial
setup failure remain in `/tmp/abyss-0.9.0-published-consumers*.log`.
