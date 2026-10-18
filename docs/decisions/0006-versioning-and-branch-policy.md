# 6. Date-versioned releases, LTS-tracking `main`, and branch-per-line

- Status: Accepted
- Date: 2026-10-18
- Supersedes: the branch and version parts of ADR 0002 (its Node.js line policy is unchanged)
- Reference: [docs/versioning.md](../versioning.md) — formats, tables and procedures

## Context

This repository ships a vcpkg port whose content is fully determined by two upstream choices:
which Node.js source tree is built, and which vcpkg release the dependency graph resolves
against. Everything else in it exists to make those two work together on six platform legs.

That has three consequences for versioning, and the first draft of a policy only addressed
the third:

1. A semver-shaped number for the repository itself would have to encode "Node.js moved a
   patch", "vcpkg moved a month" and "a portfile fix landed" in one place. Whoever writes the
   release notes then has to decide whether a gyp patch is minor or patch. The information a
   consumer needs is not the magnitude of the change, it is *which* Node.js and *which* vcpkg.
2. `main` cannot serve both "newest LTS" and "stable for a consumer who pinned last year".
   Node.js itself solves this with multiple maintained lines; so does every distribution that
   packages it.
3. A tag that only carries a date cannot be resolved back to a buildable state months later,
   because the date says nothing about the two upstreams.

Facts that shaped the decision:

- vcpkg's manifest version for the port is `26.12.0` — the Node.js version, which is what a
  port wrapping upstream should say (`openssl 3.4.1`-style) and what consumers see. It is not
  the repository's release version, and the two must not be conflated.
- `port-version` already carries vcpkg's packaging counter, so a portfile fix has a correct
  place to go without inventing a fourth number.
- Node.js publishes its release schedule, so "how long is this line supported" has an
  external answer rather than a self-invented one.
- The repository already needs a machine-readable pin record for CI and for the release
  watcher; a hand-maintained one drifts silently, which is why every field except the release
  date is checked against its source of truth (portfile, manifest, workflow default).

## Decision

1. **The repository's own version is a date**: `YYYYMMDD`, plus `.N` for a second release on
   the same day. It appears in `versions.json`, in tags and in release notes — never in the
   manifest, which keeps the Node.js version.
2. **`versions.json` at the repository root records the three numbers** (release date,
   Node.js, vcpkg release + commit) and the derived facts worth keeping (source SHA512, V8
   version, `NODE_MODULE_VERSION`, napi version, Node.js LTS dates). It is checked by
   `tools/check_repo.py` against the portfile, the manifest and the workflows' pin.
3. **Tags are `<release>_<node>_vcpkg-<vcpkg>`, annotated and immutable**, one GitHub Release
   per tag. They are the only immutable statement this repository makes.
4. **`main` tracks the current Node.js LTS line's latest patch and the newest vcpkg release.**
   Node.js and vcpkg upgrades happen only on `main`, always as explicit changes that pass the
   matrix — "tracking" is a commitment to bump promptly, not to automate.
5. **Each frozen line is a branch named for its pair** (`26.12.0_vcpkg-2026.07.29`), and it
   stops tracking versions. It accepts security and build fixes that keep the pair, and is
   still built and tested.
6. **A retired branch is renamed under `legacy/`** and becomes read-only, with a final tag. It
   is never deleted: old clones and tags keep working, and its history documents how the line
   ended.
7. **Support follows Node.js's schedule**: a line is supported while Node.js supports it
   (Active + Maintenance LTS), then it goes `legacy/`.

## Consequences

- A consumer has one question to answer — "newest LTS" (`main`) or "reproducible pair"
  (a branch or a tag) — and the tag tells them exactly what is inside.
- Release notes become mechanical: three numbers, the CI run, the diff since the previous tag.
  No discussion about whether a change deserves a minor bump.
- Every Node.js line transition costs one branch creation and one upgrade commit, and both
  are recorded; the repository accumulates lines the way Node.js does.
- The date version says nothing about compatibility. That is deliberate — compatibility is
  defined by the pair in the tag — but it does mean the release notes must always state the
  pair, and `versions.json` must be right. The lint exists for that reason.
- Maintaining a branch means maintaining its CI: the workflows have to run on `*_vcpkg-*` as
  well as `main`, otherwise "still built and tested" in decision 5 is a claim without a check.
