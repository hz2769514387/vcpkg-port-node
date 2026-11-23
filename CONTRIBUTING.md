# Contributing

Read [AGENTS.md](AGENTS.md) first: it is the project's rulebook, written for whoever works here
next — human or agent — and it explains why the rules exist rather than just what they are. This
file is the short version for a pull request.

## The shape of a change

- **`main` is protected.** Everything lands through a pull request with green CI, and the branch
  rule has no bypass actor — the release preparation included, which is why it is a pull request
  like any other. The one exception is the tag itself: a tag names a commit, so nothing but the
  maintainer can make it.
- **One change per pull request.** A Node.js bump and a vcpkg bump in one branch is two reviews in
  one, and the second one hides in the first.
- **A packaging change bumps `port-version`** in `ports/node/vcpkg.json`. That is what makes the
  package identity change; without it vcpkg hands consumers the old package from its cache.
- **The version tree follows the port.** `tools/version_tree.py` rewrites `versions/n-/node.json`;
  Lint fails if it is stale.
- **`CHANGELOG.md` gets an entry when a tag is cut**, not per pull request — the releases are the
  unit of change.

## What CI will tell you

Lint is seconds and catches the mechanical half: `versions.json` disagreeing with the portfile, a
stale version tree, repository hygiene, a broken release watcher. The three matrix workflows are
hours and are the real answer; a pull request that changes `ports/` runs all of them.

If a leg fails, the run's single merged log archive is the place to look — `docs/ci.md` explains
how to read it, and what each leg actually verifies.

## When a test fails

The default is that the port is wrong, not the test. A skip is a claim about the world and needs
three things in this order: a measurement (a run id), a written reason (in the skip list or the
CMake that adds it), and the narrowest scope that explains the measurement — one cell rather than
every platform, one case rather than a directory.

Two examples worth copying. `test/cases/suite` adds three skips keyed on
`node_LIBRARY_LINKAGE` rather than on the platform, because the reason is the linkage: a shared
libnode moves node's frames into the library and makes the executable non-relocatable. The same
file skips `test-watch-mode` on the x64 macOS cells alone, where the measurement is a 60-second
upstream deadline those cells sit inside (issues #28 and #113) - every other cell still runs it.

## Language and comments

Everything in the repository is English, including commit messages and code comments. Comments
explain *why*, and a measured fact beats an assertion: a comment that says "measured, run
39500147659" is worth ten that say "should be".

## Reporting a security problem

Not in an issue — see [SECURITY.md](SECURITY.md).
