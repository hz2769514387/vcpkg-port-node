# 10. The build cells run only when a change can affect what is built

- Status: Accepted
- Date: 2026-10-28
- Amends: [0004](0004-continuous-integration.md)'s tiering. The two tiers stay; what changes is
  when the expensive one is worth paying for.

## Context

Every pull request ran the full set of cells: six Release cells with Node.js's own suite, five Debug
cells and eight matrix cells. Cold, that is about nine hours of runner time per pull request, and it
is the right price for a change to the port - a patch that stops applying, an overlay that moves, a
toolchain assumption that breaks, and only a cell that builds the thing will say so.

It is not the right price for a paragraph. A pull request that edits `docs/ci.md` cannot change a
compiled byte, and the thirteen cells that ran for it were thirteen green ticks carrying no
information. In this repository's own history that happened repeatedly: the branch pass alone
produced four documentation pull requests whose noise-to-signal ratio was zero, each costing the same
as a port change.

The tiering in [0004](0004-continuous-integration.md) already distinguishes cheap from expensive
(Lint versus the build cells); nothing about it said *when* the expensive tier earns its cost.

## Decision

The three build workflows (`ci.yml`, `debug.yml`, `matrix.yml`) trigger only when a path that can
affect the build or the tests changes:

```
ports/**        the ports themselves
test/**         the consumer project, its manifest and its presets
tools/**        the scripts lint runs and the workflows call
.github/**      the workflows and the composite actions
versions.json   the recorded pins
versions/**     the version-tree records
```

Everything else - `docs/**`, `README.md`, `CHANGELOG.md`, `AGENTS.md`, `CONTRIBUTING.md`,
`SECURITY.md`, `CODE_OF_CONDUCT.md`, `LICENSE` - runs **Lint only**, which is the tier that can
actually fail on them (`check_repo.py`, `version_tree.py --check`, `check_secrets.py`,
`check_workflows.py`, `overlay_table.py --check`).

Scheduled and manual runs are unfiltered: a weekly run or a `workflow_dispatch` still builds
everything, because their purpose is to notice drift rather than to judge a change.

## Consequences

- A documentation pull request costs minutes instead of nine hours, and its checks say what they
  mean: Lint green, nothing else claimed.
- **The guarantee is now conditional, and the condition is written down**: "the full matrix is green
  on `main`" holds for every commit that touched a build-affecting path. A docs-only commit on `main`
  has no matrix result, because it has no matrix question.
- The filter is a list of paths, and a list can be wrong in one direction: a file that *can* affect
  the build but is not listed would silently stop being built. That is the failure mode to watch.
  Two things keep it honest: the list is short and lives in three workflow files that are themselves
  under `.github/**`, so changing the filter reruns the build cells; and anything added at the
  repository root that a build reads (`vcpkg.json`, a toolchain file) has to be added here in the
  same commit.
- Branch protection is unaffected: `hygiene` (Lint) is the required check, and it runs on every
  change, documentation included.
- Skipping cells on a pull request does not weaken `main`: a merge of a docs-only change leaves the
  last build result for that tree unchanged, and that result was green.
