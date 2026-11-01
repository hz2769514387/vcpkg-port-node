# AGENTS.md — working rules for this repository

Read this before changing anything. The reasoning behind each rule is in `docs/` and
`docs/decisions/`; this file says what to do, not why.

## 1. Non-negotiable

This is a **public GitHub repository**: everything that lands here — commits, pull requests,
issues, releases — is public and permanent.

- Nothing unlawful, hateful, violent, political or sexually explicit. No political commentary,
  anywhere.
- No reverse engineering, no attacking or scanning third-party systems, no retry loops against a
  remote service.
- **Never write outside this repository** — no upstream issues or pull requests, no pushes to other
  repositories — unless the maintainer asks for it in the current session.
- Never commit credentials, tokens, cookies or keys, not even "temporarily". Two scanners enforce
  it: `.githooks/` over the staged lines (enable once per clone with
  `git config core.hooksPath .githooks`) and `tools/check_secrets.py --all` over the whole history
  in lint. A flagged value that is not a secret gets reworded, not excluded.
- Respect `robots.txt`, upstream licences and NOTICE files.
- Silence is not permission: an action not sanctioned here, by the maintainer, or by a licence is
  forbidden.

`.user_local/`, when present, is the maintainer's untracked working copy: read it, including
`.user_local/用户原话*.txt`, and never edit it. It also carries how work is expected to be done in
this checkout.

## 2. File hygiene

- **English only** in tracked files — code, comments, docs, commit and issue text. Personal notes in
  Chinese belong in `.user_local/`; the one exception is a literal path into it.
- **`README.zh-CN.md` is the single translated file**, by decision: the repository's front door is read
  before anything else, and a Chinese README is ordinary practice for the audience this project serves.
  The English `README.md` stays authoritative and links to it, the translation says so in its first
  paragraph, and `tools/check_repo.py` holds the allowlist (`TRANSLATED_FILES`) that keeps this from
  becoming a general permission. A second entry there is a decision, not a convenience.
- **LF only** (`.gitattributes`: `text=auto eol=lf`). A CR is a defect: patches are applied with
  `git apply` and `versions/` holds git tree hashes, so a stray CR changes results per machine.
- UTF-8, no BOM, trailing newline. No empty directories, no build outputs, no downloaded sources.

## 3. What this repository is

The Node.js source tree (V8 included) built as a **linkable library**, delivered as vcpkg **overlay
ports**, so a consumer writes `find_package(unofficial-node CONFIG REQUIRED)` and links
`unofficial::node::node`. It has to be an overlay: V8 is a Node-maintained fork with no externalize
channel, so no curated-registry port can replace the tree.

Current target: Node.js **v26.13.0** on vcpkg **2026.10.16**. Versions, branches and tags follow
[docs/versioning.md](docs/versioning.md).

## 4. Workflow

Maintenance period, since the `20261024` tag:

- Everything through a pull request; `main` is protected. Only the release commit and the tag are
  the maintainer's alone.
- A pull request carries what and why, a linked issue, green CI, and a changelog entry at tag time.
- The full matrix is expected green on `main` for every commit that touched a build-affecting
  path. A documentation-only change runs Lint alone - it has no matrix question
  (ADR 0010). A red leg is an incident, not a background state.
- A change that breaks a documented guarantee amends the guarantee in the same pull request.

Where things go:

- **Decisions and reference material → `docs/`, in English.** Decisions are ADRs under
  `docs/decisions/`; an accepted ADR is never edited — a changed mind gets a new ADR that supersedes
  it.
- **Work items → GitHub issues**, one per verifiable task, with a closing condition.
- **Not the wiki**: it is a separate repository, so it is not cloned, not in the commit history and
  not reviewable in a pull request.

## 5. Invariants

- Build route is **`configure.py` → `gyp -f ninja` → `ninja`** on all three platforms. No gyp→CMake
  translation layer.
- `ports/node` is **self-contained**: portfile, manifest, usage, patches, cmake modules, and nothing outside its own
  directory. Triplets and toolchains belong to the consumer, never to the port.
- **Consumers use stock vcpkg triplets.** Compiler discovery, the MSVC environment, manifest
  embedding, stack size, C++20 — all of that is the port's job.
- Exported config is `unofficial-node`; targets live in `unofficial::node::`.
- **A packaging change bumps `port-version`** in the same commit (0 is implicit, so the first
  revision is 1); an upstream version bump resets it to 0.
- Editing `ports/` invalidates the version tree — rerun `tools/version_tree.py`.
- Node.js sources are downloaded and hash-verified by the port. **Never vendor a Node.js tree.**
- `versions.json` records the three pins, and `tools/check_repo.py` fails when it drifts from the
  portfile, the manifest or the CI pin.

## 6. Before you say "done"

- Run what CI runs, from `test/`, when it is affordable: `cmake --preset <triplet>`,
  `cmake --build --preset <triplet>`, then `ctest --test-dir build/<triplet> -C Release -LE
  node-suite`. The suite (`-R node-suite`) is worth its hour before anything touching the build.
  Keep `-j` at what CI uses: REPL cases fail on timing above it.
- Say what changed, what you verified, and what you did **not** verify.
- Evidence over reasoning: exact commands, paths, versions, log excerpts.
- If verification needs a heavy build or a CI run, hand it over explicitly instead of implying
  success.
