# AGENTS.md — working rules for this repository

Entry point for AI agents (and humans acting like one) working here. Read it before
changing anything.

## 1. Non-negotiable rules

This is a **public GitHub repository**. Everything that lands here — commits, pull
requests, issues, wiki pages, releases — is public and permanent. Therefore:

- Nothing unlawful, hateful, violent, political, or sexually explicit. No political
  commentary of any kind, anywhere.
- No reverse engineering. No attacking, scanning, or probing third-party systems. No
  retry loops that hammer a remote service.
- **Never write to anything outside this repository** — no posting, commenting, filing
  upstream issues or pull requests, no pushes to other repositories — unless the
  maintainer explicitly asks for it in the current session.
- Never commit credentials, tokens, cookies, or private keys, not even "temporarily".
  Enforced twice: the pre-commit hook (`.githooks/`, enabled once per clone with
  `git config core.hooksPath .githooks`) scans the staged lines, and lint.yml runs
  `tools/check_secrets.py --all` over the whole history on every push. A value the
  scanner flags but that is genuinely not a secret gets reworded (env read,
  placeholder) rather than excluded.
- Respect `robots.txt`, upstream licenses, and upstream NOTICE files when vendoring or
  patching code.
- Silence is not permission. If an action is not clearly sanctioned by this file, by the
  maintainer's instructions, or by the relevant license, treat it as forbidden.

## 2. Where to look first

1. **`.user_local/`** — if that directory exists, this checkout is the maintainer's
   personal working copy. It is untracked and holds the maintainer's own notes, including
   the authoritative record of standing decisions. Read
   `.user_local/用户原话*.txt` and follow it, but **never edit it**: it is the user's to
   maintain. It also records how work is expected to be done here (git workflow,
   verification expectations, local tooling).
2. If `.user_local/` does not exist, you are in a plain clone: behave like an outside
   contributor and follow this file (plus `CONTRIBUTING.md`, added at the first release).

## 3. Language and file hygiene

- **Every tracked file is English** — code, comments, documentation, commit messages, pull
  request and issue text. No CJK in tracked files. Personal notes in Chinese belong in
  `.user_local/`, which is untracked. The one permitted exception is a literal path into
  `.user_local/` when telling a reader where to look.
- **LF only.** `.gitattributes` sets `text=auto eol=lf`. A CR in a tracked file is a
  defect, not a style preference: our patches are applied with `git apply`, and the
  version-tree hash under `versions/` is a git tree object hash, so a stray CR changes the
  result from one machine to the next.
- UTF-8, no BOM, trailing newline at end of file.
- Do not commit empty directories; a directory appears together with its first real
  content.
- Do not commit build outputs, downloaded sources, or local editor state (see
  `.gitignore`).

## 4. What this repository is

Wrap the **Node.js source tree** (including its V8) and build it into a **linkable
library**, delivered as **vcpkg overlay ports**, so a consumer project can write
`find_package(unofficial-node CONFIG REQUIRED)` and link `unofficial::node::node`.

It is an overlay port on purpose: `ports/node` is meant to be referenced through
`overlay-ports`. V8 is a Node.js-maintained fork with no externalize channel, so the
Node.js source tree can never be replaced by curated-registry ports.

Current target: Node.js **v26.12.0** on the vcpkg baseline **2026.07.29**. The reasoning
lives in `docs/decisions/`.

## 5. Workflow: development period vs maintenance period

The **development period ended on 2026-10-24** with the first release tag,
`20261024_26.12.0_vcpkg-2026.07.29`. Everything below the line is now the rule.

Development period (2026-10-… → 2026-10-24, closed):

- Work directly on `main`. Small, frequent commits. `main` is allowed to be broken.
- CI may be red while work is in flight; failures are worked down, not hidden.
- Self-review is acceptable.
- No interface stability is promised to consumers; change whatever needs changing.
- No tags — and then exactly one, cut by the maintainer with the checklist in
  `docs/versioning.md` §4 satisfied.

Maintenance period (now):

- Everything through pull requests; `main` protected. The release commit and the tag are the
  maintainer's, and are the only things that do not go through a pull request.
- Conventional review: description, linked issue, green CI, changelog entry at tag time.
- The community files exist and are part of the contract: `CONTRIBUTING.md`,
  `CODE_OF_CONDUCT.md`, `CHANGELOG.md`, `SECURITY.md`, and the issue and pull request templates.
- A change that does not keep a documented guarantee gets the guarantee amended in the same pull
  request, not afterwards.
- The full matrix is expected green on `main`. A red leg is an incident, not a background state.

Where things go:

- **Durable decisions and reference material → `docs/` in this repository, in English.**
  Versioned with the code they describe, reviewable in a pull request, searchable forever.
  Decisions are recorded as ADRs under `docs/decisions/`.
- **Work items → GitHub issues.** One issue per verifiable task, with a closing condition.
  Research spikes get an issue too; the conclusion is written up under `docs/`.
- **Not the wiki** for decisions or research: a GitHub wiki is a separate repository, so it
  is not cloned with the code, is not in the commit history, and cannot be reviewed in a
  pull request. It is reserved for user-facing material, if we ever need it.

## 6. Technical invariants

- Build route: **gyp → ninja** (`configure.py` → `gyp -f ninja` → `ninja`) on all three
  platforms. Do not reintroduce a gyp→CMake translation layer; that route was tried and
  removed.
- `ports/node` is **self-contained**: `portfile.cmake`, `vcpkg.json`, `usage`, `patches/`,
  `scripts/` — and nothing referencing paths outside its own directory. It must not carry
  triplets or toolchains; those belong to the consumer.
- **Consumers use stock vcpkg triplets.** Anything a consumer would otherwise have to
  hand-copy — compiler discovery, the MSVC command-line environment, manifest embedding,
  stack size, the C++20 requirement — is the port's job to provide.
- The exported CMake config is `unofficial-node`, with targets in the
  `unofficial::node::` namespace. vcpkg requires the `unofficial-` prefix whenever upstream
  ships no CMake config of its own.
- Editing anything under `ports/node` invalidates the version-tree hash: rerun
  `tools/version_tree.py`, and let CI's `--check` catch it if you forget.
- **A packaging change bumps `port-version`.** vcpkg's package identity comes from the
  manifest, not from the portfile text: fix a portfile option, add a patch, change an install
  rule — and move `"port-version"` in the same commit (0 is implicit, so the first packaging
  revision is `1`). Without it, an installed tree or a binary-cache entry built from the old
  portfile can still count as current, and the fix silently does not reach anyone until some
  other input changes. An upstream version bump does not need it; a build-flag or packaging
  change under a released version does.
- Node.js sources are downloaded and hash-verified by the port. Never vendor a Node.js tree
  into this repository.
- **Versions, branches and tags follow [docs/versioning.md](docs/versioning.md)** (decision:
  ADR 0006). The release version is a date, the port's manifest version stays the Node.js
  version, `main` is the only branch that upgrades Node.js or vcpkg, and tags are
  `<release>_<node>_vcpkg-<vcpkg>`. `versions.json` records the pins and
  `tools/check_repo.py` fails when it drifts from the portfile, the manifest or the CI pin.

## 7. Before you say "done"

- Run the same thing CI runs when it is affordable:
  `cmake --preset <triplet> && cmake --build --preset <triplet>` then
  `ctest --test-dir build/<triplet> -C Release -LE node-suite` from `test/`. A preset is named
  after the vcpkg triplet it selects. The suite
  (`-R node-suite`) is what decides the result is still Node.js, and it is worth its hour
  before anything that touches the build.
- Say what changed, what you verified, and what you did **not** verify.
- Prefer evidence to reasoning: exact commands, file paths, versions, log excerpts.
- If verification needs a heavy build or a CI run, hand it over explicitly instead of
  implying success.
