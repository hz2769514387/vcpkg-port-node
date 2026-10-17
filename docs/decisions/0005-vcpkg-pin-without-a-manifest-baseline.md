# 5. Pin vcpkg by the checkout, not by a manifest baseline

- Status: Accepted
- Date: 2026-10-17
- Supersedes: [0003](0003-vcpkg-baseline-policy.md) — its pin and its deliberate-upgrade rule
  stand; only the manifest-baseline mechanism is replaced.

## Context

0003 pinned the vcpkg release *in the consumer test project's manifest*, as
`builtin-baseline`. Measured 2026-10-17 against a vcpkg obtained the other legitimate way - a
release tarball downloaded from vcpkg's GitHub page, which cannot be `git clone`d:

- a commit `builtin-baseline` fails with `failed to \`git show\` versions/baseline.json …
  fatal: not a git repository`;
- a dated baseline is rejected outright: `the top-level builtin-baseline (2026.07.29) was
  not a valid commit sha: expected 40 hexadecimal characters`;
- `overrides` are rejected without a baseline: `was rejected because it uses "overrides" and
  does not have a "builtin-baseline"`.

So on the built-in registry *any* manifest-side pinning requires a git checkout of vcpkg.
That is a vcpkg property rather than a defect here, but it was a requirement this
repository imposed on everyone who ran its test project - including from an IDE, where the
failure appears as an unexplained `git show` error on the first dependency.

The observation that settles the direction: consuming a release tarball is legitimate and
`vcpkg --version` reports that release, so the pin can live in *which vcpkg is used* instead
of in the manifest. CI already enforces exactly that by checking out the pinned commit.

## Decision

- **CI checks out the pinned vcpkg commit**, and the release is named in ADRs and in
  `docs/ci.md`. That is the pin, and it stays exact.
- **The manifest carries neither `builtin-baseline` nor `overrides`.** The test project
  therefore runs against whatever vcpkg `VCPKG_ROOT` points at, which is what someone with a
  release tarball has.
- **Running the test project against another vcpkg release is permitted**, and is no longer
  a configuration error - but it changes every dependency version, so results are only
  comparable against the pinned release. Said so in `test/vcpkg.json`'s description and in
  `test/README.md`.
- **Upgrading the pin stays deliberate**: the CI commit and the documented release move
  together, followed by a rebuild of the whole matrix.
- **Nothing else changes**: overlay pins under `ports/` remain deliberate and reviewed, the
  externalized dependency versions are still recorded under `docs/`, and the ABI reasoning in
  0003 still holds.

## Consequences

- A contributor no longer needs a git checkout of vcpkg; a release tarball works and an IDE
  configures out of the box. This is the point of the change.
- The repository can no longer *enforce* the dependency set on someone running the test
  project; it relies on the documented pin and on CI. That is the accepted cost, and it is
  small: what the port builds and what CI verifies is decided by the checked-out commit.
- One class of silent drift disappears: a baseline that lags the CI checkout acts as a
  minimum-version floor over it, which is hard to reason about and was invisible in the
  build output.
