# Versions, branches, tags

This repository ships one thing — a vcpkg port that builds a *specific* Node.js source tree
against a *specific* vcpkg release — so its own "version" cannot mean what it means for a
library. It is three numbers in a fixed relationship, and the rules below exist to keep the
relationship visible: which Node.js, which vcpkg, and which build of this repository.

Status: **active**. The formats, the enforcement in [§7](#7-what-is-enforced-and-what-is-not)
and the three decisions that were open in the first draft (§8) are settled; the decision to
adopt the scheme is [ADR 0006](decisions/0006-versioning-and-branch-policy.md).

## 1. The three numbers

| Number | Where it lives | Format | What it identifies |
|---|---|---|---|
| **Release version** | `versions.json`, tags, release notes | `YYYYMMDD`, plus `.N` for a second release on the same day (`20261018.1`) | *this* build of the repository. There is no semantic versioning here on purpose: the thing that changed is either Node.js, vcpkg, or a packaging fix, and each of those is recorded separately |
| **Node.js version** | `ports/node/vcpkg.json` `version`, `versions/n-/node.json`, `versions.json` | Node's own `MAJOR.MINOR.PATCH` | the source tree that is built. vcpkg consumers see this as the port's version, which is what a port wrapping an upstream project should say |
| **vcpkg release** | `versions.json`, the workflows' `vcpkg-commit` default, ADR 0003 | vcpkg release tag (`2026.07.29`) + its commit | the registry snapshot every dependency resolves against |

Two more that are easy to confuse with the above:

- **`port-version`** (`ports/node/vcpkg.json`) is vcpkg's *packaging revision counter* at an
  unchanged Node.js version — `26.12.0#1`, `#2`. It is not the release version: it exists so a
  portfile fix produces a different package identity (AGENTS.md, section 6).
- **`versions/`** is the vcpkg registry layout (one JSON per port, with git-tree hashes) that
  makes `overlay-ports` resolution work. **`versions.json`** (repository root) is this
  project's own record of the three numbers. Same name, different jobs.

`versions.json` also records what is derived but expensive to re-derive: the source URL and
SHA512, V8's version, `NODE_MODULE_VERSION`, the napi version, and Node.js's LTS dates.

### Why a date and not `1.0.0`, `1.1.0`, ...

A semver-shaped number would have to encode "Node.js moved up a patch" and "the portfile
changed" in the same place, and then someone has to decide whether a gyp patch is a minor or a
patch release. The date answers the only question a consumer of this repository asks — *is this
newer than what I have* — and the three-record in `versions.json` answers the question that
actually matters — *what is in it*.

## 2. `versions.json`

One file, at the repository root, machine-read and hand-edited only in the `port` block:

```json
{
  "port":  { "version": "20261018", "released": false,
             "manifest_version": "26.12.0", "manifest_port_version": 0 },
  "node":  { "version": "26.12.0", "released": "2026-10-14", "lts": false,
             "lts_start": "2026-10-28", "eol": "2029-04-30",
             "url": "https://nodejs.org/dist/v26.12.0/node-v26.12.0.tar.xz",
             "sha512": "c3c4…", "v8": "14.6.202.34",
             "module_version": 147, "napi_version": 8, "npm": "11.20.0" },
  "vcpkg": { "release": "2026.07.29", "commit": "9e593bb…" }
}
```

`port.released` is `false` until the first tag exists — during the development period the
version is the date the record was last touched, and nothing claims it was released.
`node.lts_start` / `node.eol` are Node.js's published schedule for the line (they are what §6
is derived from), not something this repository decides.

Rules:

- **One writer per field.** `port.version` is set when a release is prepared and at no other
  time. Everything else is *derived*: a Node.js bump changes `node.*` and the portfile
  together; a vcpkg bump changes `vcpkg.*` and the workflows' default together.
- **It is checked, not trusted.** `tools/check_repo.py` compares it against the portfile
  (Node.js version and SHA512), `ports/node/vcpkg.json` (`version`, `port-version`) and the
  `vcpkg-commit` default in `.github/workflows/build-test.yml`. Drift fails Lint.
- **It does not replace the ADRs.** The *policy* behind the pins is in ADR 0002 (Node.js
  line), ADR 0003 (vcpkg baseline); `versions.json` is the current value of those decisions.

## 3. Branches

| Branch | Tracks | Accepts | Guarantee |
|---|---|---|---|
| `main` | the current Node.js LTS line's latest patch, and the newest vcpkg release | everything; version upgrades happen **only here** | builds and the full matrix pass (development period: the matrix may be red, but never silently) |
| `<node version>_vcpkg-<vcpkg release>` e.g. `26.12.0_vcpkg-2026.07.29` | frozen at that pair | security fixes, build fixes that keep the pair | still builds and passes its tests; **no Node.js or vcpkg line upgrades** |
| `legacy/…` | whatever it was | nothing — read-only | none. It may not build; it is kept for reference |

- **A branch's name is its lineage, not a live contract.** It records the (Node.js, vcpkg)
  pair `main` was on when the line was opened. **Backports on a maintained branch may bump a
  dependency version** — a security fix in an overlay port, typically — and the bump is recorded
  in that branch's `versions.json`, tagged, and released like any other change. The name does
  not move: it is what the line was cut from, not a promise about every commit on it. What a
  branch does not do is follow a new Node.js line or a new vcpkg release; that is `main`'s job.
- **`main` is the only branch that upgrades.** That is the whole point of the split: a
  consumer who pins a branch gets reproducibility, a consumer who pins `main` gets the newest
  LTS.
- **Transition**: when the next Node.js LTS line arrives, cut `<old node>_vcpkg-<vcpkg>` from
  the last commit of `main` that still built the old line, then upgrade `main`. The branch is
  created *before* the upgrade commit, so the branch and the tag on it are exactly the old
  state.

  Two notes on history: the node24 line predates this policy and was started the other way
  round — `main` was restarted from an empty commit and the old history frozen as
  `legacy/node24_vcpkg-2026.07.29` (no patch version in the name, because there was no cut
  point to record). From v26 onwards the transition is a branch cut, not a restart, so `main`
  keeps its history. The two older names are left as they are: renaming a frozen branch buys
  nothing and breaks every clone that references it.
- **Retiring**: a maintained branch becomes `legacy/` when Node.js itself reaches end of life
  for that line (§6) or when the maintainer decides. Retiring means: tag the final state,
  rename the branch with the `legacy/` prefix, and let it go read-only. Do not delete it —
  tags and old clones keep working, and the history is the documentation of how a line ended.
- CI runs the fast tier on `main` and on `*_vcpkg-*` branches, and never on `legacy/`. A
  maintained branch that is not tested is not maintained. The weekly tiers (Debug matrix,
  Node.js's own suite) stay on `main`: they cost hours per run, and a branch frozen at a pair
  that already passed them does not re-earn that.

## 4. Tags and releases

- **Format**: `<release version>_<node version>_vcpkg-<vcpkg release>`, for example
  `20261018_26.12.0_vcpkg-2026.07.29`.
- **Annotated**, created on the commit the matrix passed on, never moved and never deleted. A
  tag is the only immutable statement this repository makes; branches and `main` move.
- **One GitHub Release per tag**, with the same name as the tag. Body: the three numbers, the
  CI run that verified it (link), what changed since the previous tag, and any delta in the
  documented limits. During the development period there are no tags at all (the maintainer
  decides when the first one is worth cutting); the format applies from then on.
- Tags are cut for **every maintained-branch backport too** — the branch name stays, the tag
  identifies the exact state.
- **Cutting a tag and publishing a release is the maintainer's decision, never an automated
  step.** The watchers report, CI verifies, and the checklist below says what has to be true;
  none of them tags anything. No tag exists while the repository is in its development period.

Preparing a release is a checklist, and the lint covers half of it:

1. the matrix is green on the commit that will be tagged (link it in the release body);
2. `versions.json`: `port.version` = today's date (`.N` if today already has one),
   `port.released` = `true`;
3. the README's Status table (the human mirror of the pins) still matches `versions.json`;
4. `tools/version_tree.py` and `tools/check_repo.py` pass — the second one is what catches a
   half-finished Node.js or vcpkg bump;
5. tag, release, and make sure the release body names the CI run.

## 5. What `main` tracking means

`main` follows two upstreams, and neither of them is automatic:

- **Node.js LTS.** The current Active LTS line's latest patch. Patch bumps (`26.12.0` →
  `26.12.1`) are routine: version, URL and SHA512 in the portfile, `versions.json`, the
  version tree, the matrix. A *new line* is the branch transition in §3.
- **vcpkg releases.** The newest vcpkg release tag is the target. The upgrade is an explicit
  pull request that moves the CI default, the ADR 0003 baseline and `versions.json` together,
  because it changes every dependency version and every ABI hash (ADR 0003). "Tracking" means
  the bump happens promptly; it does not mean a bot rewrites `main`.
- **Holding back is allowed and must be written down.** If a vcpkg release breaks a leg, or
  ships a dependency the Node.js line cannot use, `main` stays on the previous release and the
  reason goes in the pin's ADR or an issue — never a silent lag.

Where the watching actually happens: `.github/workflows/node-release-watch.yml` polls
`nodejs.org/dist/index.json` daily, and `.github/workflows/vcpkg-release-watch.yml` asks
GitHub's API for the latest `microsoft/vcpkg` release daily. Each makes one request per run
(the vcpkg one makes a second only when a newer release exists, to fetch its commit for the
upgrade) and files or updates exactly one issue per finding. Neither one edits a pin: a
watcher says what is available, a reviewed change moves it.

## 6. Support window

A line is supported while Node.js supports it: Active LTS plus Maintenance LTS, which is 30
months from the major's release. `main` = the current LTS; the previous LTS is expected to be a
maintained branch; anything older is `legacy/`. The exact dates for the current line are in
`versions.json` (`node.lts_start`, `node.eol`) so the policy does not have to be re-derived
from Node's release schedule by hand.

## 7. What is enforced, and what is not

| Rule | Enforced by |
|---|---|
| `versions.json` agrees with the portfile, the manifest and the CI pin | `tools/check_repo.py` (Lint workflow) |
| the version tree hash matches the port content | `tools/version_tree.py --check` (Lint workflow) |
| a packaging change bumps `port-version` | AGENTS.md, review (not a tool) |
| tags are immutable, releases carry a CI link | review |
| a maintained branch still builds | CI on `*_vcpkg-*` |
| an upstream release does not go unnoticed | the two watchers (§5); Lint runs both in `--dry-run` so a broken parser fails there first |

## 8. Decisions taken on the first draft

The first draft of this policy left three things open; the maintainer settled them on
2026-10-18, and they are folded into the sections above:

1. **Backports may bump dependency versions** (§3). A maintained branch is not frozen at every
   version: a security fix in an overlay port is a backport, it is recorded in that branch's
   `versions.json`, and it is tagged. What a branch does *not* take is a new Node.js line or a
   new vcpkg release.
2. **vcpkg releases are watched** (§5). `.github/workflows/vcpkg-release-watch.yml` runs daily
   against GitHub's API, files one issue per available release with the commit the upgrade
   needs, and never edits a pin itself.
3. **Tags and releases are the maintainer's explicit decision** (§4). No automation creates
   them: not the watchers, not CI. The checklist above is what has to be true first; cutting
   the tag is a human act, and that is deliberate — a tag is the only immutable statement this
   repository makes.
