# 2. Track the Node.js v26 line and pin the exact patch

- Status: Accepted
- Date: 2026-10-15
- Supersedes: —

## Context

Node.js ships a new major every six months and patch or minor releases on each maintained
line in between (from v27 on, the cadence changes to one major per year, always LTS). A
port that wraps Node.js has to decide which line to follow, how tightly to pin it, and who
notices when upstream moves.

Facts that shaped this decision:

- The port's version number *is* the upstream Node.js version (`vcpkg.json` carries
  `"version": "26.12.0"`). vcpkg has no notion of a "major line", so "follow 26.x" can only
  be a policy we enforce in review and automation — not a mechanism we can configure.
- Node.js v26.0.0 shipped on 2026-05-05 and becomes Active LTS on 2026-10-28. v26.12.0
  (2026-10-07) is the newest patch as of this decision.
- Within one line, Node.js itself pins V8 (`26.x` → `14.6.202.34-node.37`) and
  `NODE_MODULE_VERSION` (147), so native add-ons stay compatible across patch releases of
  the same line. Crossing a major line breaks that.
- Patch releases inside a line routinely carry security fixes, so staying on a stale patch
  is not a neutral choice.
- Neither Renovate nor Dependabot supports vcpkg (checked 2026-10-15: Renovate's datasource
  list has no `vcpkg` entry and there is no vcpkg manager). Nothing will bump this for us
  unless we build it.

## Decision

- **Follow the Node.js v26 line.** The exact patch is pinned twice: as the `version` in
  `ports/node/vcpkg.json`, and as the source archive hash in `ports/node/portfile.cmake`.
- **Patch and minor bumps inside v26.x are expected and accepted.** Each bump is a normal
  change: bump the version, the download URL, and the SHA512; rebase the patch set; run the
  full CI matrix. Bump `port-version` when the change is packaging-only.
- **Crossing to another major line is a project, not a version bump.** A new line gets its
  own dependency audit and patch rebase; the previous line is frozen in a `legacy/` branch
  and never maintained again.
- **Staleness is detected by us.** A scheduled workflow compares the pinned version against
  `https://nodejs.org/dist/index.json` and opens an issue or pull request when a newer
  `26.x` exists. Until that workflow exists, checking is a manual step.
- A bump is complete only when the official Node.js test suite passes across the full
  platform matrix, and every skip-list entry has a written reason.

## Consequences

- Consumers get security fixes within days of upstream, without waiting for a project
  release cycle.
- Every bump costs a full CI run — V8 dominates build time — plus a patch-set review.
  Batching bumps is acceptable; sitting on one for months is not.
- Because the patch is pinned exactly, `process.versions.node` is reproducible for a given
  commit of this repository, which is what the consumer tests assert against.
- There is automation to build: the release watcher does not exist yet, so this policy is
  currently upheld by hand.
