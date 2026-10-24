# Contributing

Read [AGENTS.md](AGENTS.md) first: it is the project's rulebook, written for whoever works here
next — human or agent — and it explains why the rules exist rather than just what they are. This
file is the short version for a pull request.

## The shape of a change

- **`main` is protected.** Everything lands through a pull request with green CI. Two exceptions,
  both the maintainer's: a release tag and the release commit itself.
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

Two examples worth copying: `test/smoke` skips only the *date* half of its ICU check on one cell
(README known limits), and `test/official_suite` adds two skips keyed on `node_LIBRARY_LINKAGE`
rather than on the platform, because the reason is the linkage.

## Language and comments

Everything in the repository is English, including commit messages and code comments. Comments
explain *why*, and a measured fact beats an assertion: a comment that says "measured, run
39500147659" is worth ten that say "should be".

## Reporting a security problem

Not in an issue — see [SECURITY.md](SECURITY.md).
