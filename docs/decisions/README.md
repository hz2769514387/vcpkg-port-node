# Architecture decision records

Short records of decisions that are expensive to reverse, in the order they were made.
Shape: context, decision, consequences (MADR flavoured). An accepted ADR is never edited —
a change of mind gets a new ADR that supersedes the old one, so the history stays readable.

| # | Title | Status | Date |
|---|---|---|---|
| [0001](0001-record-decisions-as-adrs.md) | Record decisions as ADRs in `docs/decisions/` | Accepted | 2026-10-15 |
| [0002](0002-node-version-policy.md) | Track the Node.js v26 line and pin the exact patch | Accepted | 2026-10-15 |
| [0003](0003-vcpkg-baseline-policy.md) | Pin the vcpkg baseline and upgrade it deliberately | Superseded (mechanism) by 0005 | 2026-10-15 |
| [0004](0004-continuous-integration.md) | CI lives in GitHub Actions, builds through the consumer, and gates in two tiers | Accepted | 2026-10-16 |
| [0005](0005-vcpkg-pin-without-a-manifest-baseline.md) | Pin vcpkg by the checkout, not by a manifest baseline | Accepted | 2026-10-17 |
| [0006](0006-versioning-and-branch-policy.md) | Date-versioned releases, LTS-tracking `main`, and branch-per-line | Accepted | 2026-10-18 |
| [0007](0007-toolchain-configuration-and-linkage-policy.md) | One toolchain per platform, three configurations, both linkages and both CRTs, all proven in CI | Accepted | 2026-10-18 |
| [0008](0008-icu-comes-from-vcpkg.md) | ICU comes from vcpkg, and is therefore the one dependency not built by clang-cl | Accepted | 2026-10-19 |
| [0009](0009-openssl-is-built-with-clang-cl.md) | OpenSSL is compiled with clang-cl, the compiler Node.js requires | Accepted | 2026-10-19 |
| [0010](0010-build-cells-run-when-a-change-can-affect-the-build.md) | The build cells run only when a change can affect what is built | Accepted | 2026-10-28 |
