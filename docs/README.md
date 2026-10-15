# Documentation

Design notes, decisions, and reference material for this repository. Everything here is
versioned with the code and reviewed in pull requests.

## Conventions

- English only, like every tracked file. Personal working notes live in `.user_local/`,
  which is untracked.
- One topic per file, `kebab-case.md`, listed in the index below.
- **Decisions are recorded as ADRs** in `docs/decisions/` — see
  [decisions/0001](decisions/0001-record-decisions-as-adrs.md). An accepted ADR is not
  edited; a change of mind gets a new ADR that supersedes it.
- Long-lived reference material (dependency disposition, build reference, CI reference)
  lives directly under `docs/`.
- Text that only makes sense together with one change belongs in that pull request or
  commit message, not here.

## Index

| Document | Purpose | Status |
|---|---|---|
| [decisions/](decisions/README.md) | Architecture decision records | active |
| [dependency-disposition.md](dependency-disposition.md) | Per-dependency verdict for the Node.js v26 line: externalized, overlay-pinned, or vendored — with the measurements behind each | active |
| [build.md](build.md) | How the port builds Node.js (gyp → ninja): the externalization mechanism, the platform quirks, and the fixes the port must carry | active |
| [ci.md](ci.md) | Workflows, the platform matrix, what each gate decides, caching, the release watcher | active |
| [test-suite-results.md](test-suite-results.md) | Results of running Node.js's own suite against the port-built executable, with every skip explained | active |

## Where work items live

Issues, not documents: one issue per verifiable task, with a closing condition. Research
spikes get an issue too — their conclusion is written up here as a document, because an
issue thread is where the deliberation belongs, not the outcome.
