# 0015 - Four CI gates on every push, through the consumer

Status: Accepted
Date: 2026-11-24
Supersedes: [0004](0004-continuous-integration.md)

## Context

ADR 0004 was written during the development period, when `main` was allowed to be red, no tag
existed, a full Node.js test suite was too expensive for every push, and only Windows had
completed a build. Every one of those premises has since been tested and replaced:

- The `20261118_node-26.13.1_vcpkg-2026.10.16` release put the repository in maintenance.
  A red build leg on `main` is an incident, not a background state (AGENTS.md §4).
- All six platform cells completed, including the official suite, and release-only triplets
  cut the cost of a leg enough that the suite can run on every push. The weekly suite-only
  workflow was deleted rather than maintained as a second description of the same thing.
- A dual vcpkg install on the four-core Linux runners takes 5h36m with every dependency
  cached, against a six-hour per-job ceiling: three runs measured 6h00m (cancelled), 5h47m
  (passed) and 6h05m (cancelled), and arm64 never finished. Linux Debug is a written-down
  gap, not an experimental leg waiting to be promoted.
- A job that calls a reusable workflow accepts neither `strategy` / `matrix` nor
  `continue-on-error`. Adding either produces a run with zero jobs and a "workflow file
  issue", so blocking has to travel through an input to the reusable workflow.
- vcpkg removed the `x-gha` binary cache provider; `clear;x-gha,readwrite` also clears the
  files provider and rebuilds the whole graph on every run. Hashing `ports/**` into the
  cache key had the same effect for a different reason and is what made the old Debug legs
  time out.

`docs/ci.md` records the measurements and the current cell table. This ADR records the
decision those measurements changed.

## Decision

CI has four gating workflows, and each pushes a distinct claim:

- `lint.yml` — seconds, on every push and pull request including documentation-only ones.
  It owns repository hygiene, the version-tree hashes, the overlay disclosures, the CI
  table and the workflow scripts. A documentation-only change has no matrix question, so
  Lint alone is the gate (ADR 0010).
- `ci.yml` — six blocking cells (both architectures on Windows, Linux and macOS). Each
  installs through a release-only triplet, builds the consumer as Release and
  RelWithDebInfo, and runs Node.js's own suite against the Release consumer.
- `debug.yml` — four cells (both Windows and both macOS architectures) building a Debug
  consumer against a dual install. There is no Linux Debug cell.
- `matrix.yml` — twelve cells: `/MD` on Windows (2), shared libnode on every platform (6),
  and a clang-cl-built dependency graph (4). Eight block a merge — the four shared cells on
  Windows and Linux plus the four clang-cl cells; four do not — the two `/MD` cells and the
  two macOS shared cells (issue #35). The split is checked against the workflows by
  `tools/check_ci_table.py`.

All build legs call `.github/workflows/build-test.yml`, which is the only place the build
steps exist. A leg is one job and passes `runner`, `preset`, `triplet`, `consumer-configs`,
`suite-configs`, `expect-arch`, `vcpkg-commit`, `experimental` and `timeout-minutes` as
inputs. There is no `ctest-options` input; configurations that run the suite are named by
`suite-configs`, and the rest run with `-LE node-suite`.

A non-blocking leg is `experimental: true` on the **caller's input**, never
`continue-on-error` and never a `strategy`/`matrix` on the caller. The build workflows run
only when a path that can change what is built changes (`ports/**`, `test/**`, `tools/**`,
`.github/**`, `versions.json`, `versions/**`); scheduled and manual runs are unfiltered
because their purpose is to notice drift, not to judge a change (ADR 0010).

Binary caching uses `clear;files,<workspace>/vcpkg-archives,readwrite` plus `actions/cache`,
keyed by runner, pinned vcpkg commit, triplet and the test manifest — never by `ports/**`.
Every leg uploads its logs unconditionally; only the artifact upload is `continue-on-error`,
so an artifact-service failure cannot turn passing tests red. `logs.yml` merges the parts
into one archive per run, and the run summary carries the ctest counts and the first error.

Two daily watchers open an issue when a pin is out of date; they never edit a pin. CI never
tags, releases or publishes. `benchmark.yml`, `official-binary-baseline.yml` and
`flaky-probe.yml` are manually dispatched measurements, not gates.

## Consequences

- Every dimension this repository claims is verified on a build-affecting push, except the
  two Linux Debug cells and the dimensions no cell covers at all; both are named in the
  README's *Known limits* and in `docs/ci.md`.
- The slowest blocking cell takes about 155 minutes, so a pull request is gated by a
  multi-hour run. It is still cheaper than discovering a broken shared or clang-cl build
  after a release.
- Four matrix cells are allowed to be red without blocking a merge. They are still built on
  every push and still published in the run, so "non-blocking" means "not a gate", not
  "not measured".
- The cache is a speed-up, never a source of truth: a warm cache still configures, builds
  the consumer and runs ctest, and vcpkg reuses only archives whose ABI hash matches.
- Because 0004 is superseded rather than deleted, its two-tier design remains in the
  history as the reason the current gates were measured and changed.
