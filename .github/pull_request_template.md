<!--
Small pull requests are easier to review than large ones, and a change that says why is easier
than one that says what. Both are explained in CONTRIBUTING.md; this template is the checklist.
-->

## What this changes, and why

<!-- One paragraph. If it fixes an issue, link it: "Fixes #12". -->

## Evidence

<!--
The part that matters. A run id, a measurement, or the output that proves the claim — not "should
work". If the change is a skip or a documented limit, link the run that shows the failure.
-->

## What it touches

- [ ] `ports/` — a packaging change, so `port-version` is bumped
- [ ] `versions/` — `tools/version_tree.py` has been re-run
- [ ] `docs/` — an ADR, or a document that was describing something else
- [ ] CI — a workflow, an action or the tooling under `tools/`
- [ ] tests — `test/`, including the skip lists (each new skip has its reason written down)

## Checklist

- [ ] `tools/check_repo.py` and `tools/version_tree.py --check` pass
- [ ] the full matrix was run, and the failing legs (if any) are named above with their reason
- [ ] if a documented limit changed, the README's *Known limits* changed with it
- [ ] no new skip without a measurement behind it
