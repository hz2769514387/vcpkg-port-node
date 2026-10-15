# 1. Record decisions as ADRs in `docs/decisions/`

- Status: Accepted
- Date: 2026-10-15
- Supersedes: —

## Context

This repository accumulates findings that are expensive to re-derive: which Node.js
dependency can be externalized and how, which upstream patch is required and why, which
build route was chosen after the alternatives failed. An earlier cycle of this project
produced exactly that kind of material and then had to be frozen; losing the reasoning
means paying for the same experiments twice, in build hours.

Options considered for where durable decisions live:

1. **A page per topic in the GitHub wiki.** Rejected. A GitHub wiki is a separate git
   repository, so it is not cloned or forked with the code, is not part of the commit
   history, and cannot be reviewed in a pull request. Documentation that drifts away from
   the code it describes becomes archaeology at a different URL.
2. **Issues only.** Rejected as the primary store. Issues are work items; they accumulate
   deliberation and cannot be reviewed line by line. That is where the *conversation*
   belongs, not the distilled outcome.
3. **Markdown files inside the repository.** Chosen. Versioned with the code, reviewed
   through the same pull request workflow, searchable with the same tools as the source,
   and it survives cloning, forking, and moving between hosts.

## Decision

- Durable decisions are recorded as ADRs at `docs/decisions/NNNN-kebab-case-title.md`, in
  the shape: context, decision, consequences.
- `docs/decisions/README.md` is the index. Every ADR is listed there with its status and
  date, so the whole decision history reads in five minutes.
- An accepted ADR is immutable. Changing a decision means adding a new ADR that supersedes
  it and updating the index; the superseded record stays, marked as such.
- Deliberation happens in a GitHub issue or pull request; the ADR holds the outcome and
  links back to it.
- Decisions that need a long reference document — for example the per-dependency
  disposition — are written as ordinary documents under `docs/` and referenced from the
  index here.
- ADRs are written in English, like every tracked file, even though the maintainer works
  in Chinese locally.

## Consequences

- Every expensive decision has a URL, a date, and a rationale that a reviewer can argue
  with *before* it lands, rather than after.
- Writing an ADR costs time. We accept that for decisions that are expensive to reverse
  (build route, dependency strategy, version policy) and skip it for routine changes.
- The repository carries a small amount of process weight: an index to keep current, and a
  rule to respect when a previous decision is revisited.
