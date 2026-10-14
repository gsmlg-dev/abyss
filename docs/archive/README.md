# Historical acceptance archive

This directory preserves source-attributed acceptance reports, release verification and diagnostic evidence. It is excluded from the Hex package and generated user guides. Start with the [current documentation](../README.md) for supported APIs and architecture.

## Records

| Record | Context |
| --- | --- |
| [UDP runtime acceptance](udp-runtime/acceptance.md) | Final 0.8.0 gates and published-consumer verification |
| [UDP runtime progress](udp-runtime/progress.md) | Completed P0–P6 execution and earlier checkpoints |
| [Resource and performance measurements](udp-runtime/performance.md) | Controlled workload results, source identity and limits |
| [UDP hardening acceptance](udp-hardening-acceptance.md) | Earlier listener/admission/client/multicast hardening |
| [QUIC Phase 1 acceptance](phase1-acceptance.md) | Service, writer and independent application gates |
| [Published QUIC engine acceptance](published-quic-acceptance.md) | Historical dependency issue and provenance checks |
| [OTP multicast reproductions](udp-otp-multicast-defects.md) | Observed platform behavior behind supported backend restrictions |

## Evidence directories

| Directory | Contents |
| --- | --- |
| [udp-runtime/evidence/](udp-runtime/evidence/) | Baseline, P1–P6, diagnostic, matrix, performance and publication evidence |
| [udp-evidence/](udp-evidence/) | Earlier UDP hardening red/green, host, network and stress records |
| [phase1-evidence/](phase1-evidence/) | QUIC service/writer lifecycle and independent consumers |
| [published-quic-evidence/](published-quic-evidence/) | Published engine reproduction, provenance and regression checks |

## Interpreting historical status

Versions, source hashes, commands, temporary paths and PASS/FAIL/BLOCKED statements apply to their recorded run. Earlier checkpoints and failed attempts remain useful diagnostic evidence; they do not replace the final release result or prove the current checkout passes. In particular, early 0.8 checkpoints recorded an upstream QUIC blocker that the final acceptance report records as resolved.

The 0.8 release record identifies tag `0.8.0` at `7d3a29f4206457669afa60a762a78eb7b90d2690`. Its final verification records Linux/macOS regression and network/package matrix success, with 83 pre-existing strict Credo findings, native backend restrictions, performance limitations and an unpublished optional DHCP package. These are recorded results, not a new test run performed during documentation cleanup.

## Cleanup policy

The completed Phase 1 implementation plan, UDP hardening plan and P1/P5 coordination notes were removed from current documentation because their task instructions and interim statuses were superseded by shipped code, current guides and final acceptance. Their original contents remain in Git history at the pre-cleanup commit `0d6531d087db262bf09c3caa363ea8c0644f4389`.

Raw evidence is retained with its original content and filenames. Historical Markdown has an archive notice and adjusted navigation links; recorded commands and transcripts remain historical. Future generated benchmark output belongs in ignored build output, not in this immutable release archive.
