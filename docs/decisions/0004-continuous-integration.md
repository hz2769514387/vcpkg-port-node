# 4. CI lives in GitHub Actions, builds through the consumer, and gates in two tiers

- Status: Accepted
- Date: 2026-10-16
- Supersedes: —

## Context

Three questions about continuous integration had to be answered before writing it: what it
builds, how often, and what a red build means.

Facts that shaped this decision:

- A full Node.js build is dominated by V8. Measured on `x64-windows-static` with
  Node.js v26.12.0: about 40 minutes on a developer machine for Release **and** Debug, and
  the official test suite adds roughly another 15 minutes per run. That is too expensive to
  put in front of every push, and too valuable to leave to memory.
- The deliverable is a **port**. Its consumers reach it through vcpkg, so the thing that can
  break is not the compile of some translation unit - it is the whole path: overlay ports,
  manifest, stock triplet, `find_package`, link, run. A CI job that drove the port differently
  would not test that path at all.
- Neither Renovate nor Dependabot supports vcpkg (checked 2026-10-15, see ADR 0002), so the
  release watcher has to be built here as well.
- The project is in its development period: `main` is allowed to be broken, self-review is
  acceptable, and no tag exists yet (AGENTS.md, section 5).
- GitHub-hosted runners are the only sane option for three operating systems without owning
  three machines, and the repository is public, so minutes are free but the 10 GB cache and
  the six hour job limit are not.

## Decision

- **CI is GitHub Actions, and only GitHub's own actions.** No third-party action from the
  marketplace is used: workflow permissions on a public repository are worth being careful
  about, and nothing here needs one.
- **The build steps exist once**, in `.github/workflows/build-test.yml`, a reusable workflow.
  `ci.yml` and `node-suite.yml` call it with different `ctest-options`. Two gates that share
  one body cannot drift apart.
- **CI builds the port the way a consumer does**: check out the pinned vcpkg, bootstrap it,
  then configure `test/` with a stock triplet and let vcpkg build `node` as a dependency. The
  port is never driven directly.
- **Two tiers, by cost.** `lint.yml` (seconds) and `ci.yml` (tens of minutes, everything
  except Node.js's own suite) run on push and pull request; `node-suite.yml` (about an hour
  per platform) runs weekly and on demand. The suite is what actually decides that the result
  is still Node.js, so it is not optional - it is just not on every push.
- **Platforms are marked by evidence, not by hope.** Windows is the only platform with a
  completed build, so it fails the run; Linux and macOS are `continue-on-error` until one
  full build plus suite run passes on each. Silently omitting them would hide a claim the
  manifest makes.
- **The release watcher is a scheduled workflow**, not a third-party bot, and it only ever
  writes to this repository.
- CI never tags, releases, or publishes. Releasing is the maintainer's decision, and the
  development period makes a red `main` acceptable.

## Consequences

- The consumer path is exercised on every push, so "it builds in CI but not for people" is
  the failure mode least likely to survive.
- Two tiers means a broken build can sit for a week before the suite notices it. That is
  accepted: the fast tier catches build and link breakage, which is the majority.
- Marking platforms experimental makes red non-blocking there, which is a standing
  temptation to ignore them. The marker is removed per platform as soon as that platform
  passes, and the matrix entry says so in a comment.
- Binary caching through the Actions cache speeds every run up but holds several gigabytes of
  this port's own package, competing with everything else in the repository's cache budget.
