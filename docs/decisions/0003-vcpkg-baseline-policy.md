# 3. Pin the vcpkg baseline and upgrade it deliberately

- Status: Accepted
- Date: 2026-10-15
- Supersedes: —

## Context

This repository does not merely consume vcpkg ports, it depends on their exact contents:
the behaviour of the built library is determined by the version of every dependency we
externalize (`openssl`, `icu`, `libuv`, `zlib`, …), and we additionally ship overlay ports
that pin some of those dependencies to specific upstream versions. A drifting vcpkg
checkout would silently change what we build, and would do so differently on different
machines.

How vcpkg expresses this: a manifest's `builtin-baseline` names a vcpkg commit and acts as
a **minimum version floor** for every dependency; `vcpkg x-update-baseline` moves it to the
current checkout; `overrides` can force an exact version. There is no "track the newest
release" mode — the effective version set is the pinned commit, plus our overlay ports.
`port-version` tracks packaging revisions of a port at the same upstream version.

At the time of this decision the newest vcpkg release is 2026.07.29 (commit
`9e593bb18ea69cc5095e012465dcd675a822ed0d`, 2858 ports) — the same snapshot the previous
Node.js cycle used.

## Decision

- **Pin vcpkg to release 2026.07.29**, identified by commit
  `9e593bb18ea69cc5095e012465dcd675a822ed0d`. CI checks out exactly that revision, and the
  consumer test project states it in its manifest as `builtin-baseline`. *(Amended by
  ADR 0005: the test manifest carries no baseline; the pin lives in CI. See the Amendment
  section at the end of this document.)*
- **Upgrading the baseline is an explicit, deliberate change**, never background churn: a
  pull request that moves the CI pin and the `builtin-baseline` together, followed by a full
  rebuild of the whole platform matrix. *(Amended by ADR 0005: the CI pin alone moves.)* A
  baseline bump changes every dependency version,
  which changes the ABI hash of our port and can collide with the versions our overlay ports
  pin, so it is never a no-op.
- **Overlay pins are deliberate and reviewed as such.** Where vcpkg trails the version
  Node.js expects — fast-moving libraries such as `ada-url`, `nghttp2`, `llhttp`,
  `simdjson`, or `hdr-histogram` — `ports/<name>/` carries the version Node.js ships. Every
  baseline upgrade must re-examine each pin: once vcpkg catches up or overtakes it, the
  overlay entry is either deleted or re-pinned on purpose.
- **The pinned version of each externalized dependency is recorded under `docs/`**, so the
  dependency set can be audited without reading portfiles.

## Consequences

- Builds are reproducible: a given commit of this repository plus the pinned vcpkg commit
  yields one exact dependency set, on every machine.
- We do not receive upstream port improvements (build fixes, new versions) until we ask for
  them. That is accepted: the libraries that matter for security are pinned to the versions
  Node.js itself validates.
- Each baseline upgrade is a heavier change than a Node.js patch bump, and needs its own CI
  run across the full matrix — it cannot ride along with unrelated work.

## Amendment (2026-10-18): the test manifest carries no baseline

`test/vcpkg.json` deliberately has neither `builtin-baseline` nor `overrides` — ADR 0005
measured why: a manifest baseline can only be a commit or a date, and resolving either needs
a vcpkg obtained as a git checkout, which would rule out the release tarball a consumer may
legitimately have downloaded. The 2026.07.29 pin therefore lives in CI, which checks out that
commit (ADR 0005). The two sentences above that mention a manifest `builtin-baseline` are
amended accordingly and are kept as written for the record.

Also for the record: the pin list in "Decision" names `ada-url`, `nghttp2`, `llhttp`,
`simdjson` and `hdr-histogram` as overlays this repository carries. `simdjson` (and, since
2026-10-18, `libffi`, `LIEF`, `perfetto`, `mbedtls`, `frozen`, `tcb-span`) are landed;
`nghttp2`, `llhttp`, `hdr-histogram`, `ada-url`, plus the libuv/brotli patches, are still
open in issue #12. The decision itself is unchanged — those overlays are still what the
policy asks for — only the progress note is new.
