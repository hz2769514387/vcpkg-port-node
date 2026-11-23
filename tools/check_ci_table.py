#!/usr/bin/env python3
"""Check docs/ci.md's matrix table against the workflows it describes.

The table is what a consumer reads to learn which cells are enforced, and it is hand-written
prose. It drifted once already: four shared-libnode cells were marked non-blocking while
matrix.yml gated them on every pull request. Reading each job's `experimental` input and the
table's Blocking column keeps the two in step without asking a reviewer to hold twenty-two
legs in their head.

The key is the pair (workflow, triplet), because a triplet appears in exactly one job per
workflow. `debug.yml` is the exception: its four jobs share the table's single row (the stock
dual triplets), so that row is checked as a whole.
"""

import argparse
import os
import sys

try:
    import yaml
except ImportError:  # pragma: no cover - lint installs PyYAML
    print("check_ci_table: PyYAML is required", file=sys.stderr)
    sys.exit(1)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOC = os.path.join(ROOT, "docs", "ci.md")
WORKFLOW_DIR = os.path.join(ROOT, ".github", "workflows")
BUILD_TEST = "./.github/workflows/build-test.yml"
WORKFLOWS = ("ci.yml", "debug.yml", "matrix.yml")
COLUMNS = 8


def jobs(workflow):
    """Yield (job name, preset, triplet, experimental) for every build-test call."""
    with open(os.path.join(WORKFLOW_DIR, workflow), encoding="utf-8") as handle:
        document = yaml.safe_load(handle)
    for name, job in (document.get("jobs") or {}).items():
        if not isinstance(job, dict) or job.get("uses") != BUILD_TEST:
            continue
        values = job.get("with") or {}
        yield (name, values.get("preset"), values.get("triplet"),
               values.get("experimental") is True)


def table_rows():
    """Yield (workflow, leg, preset, triplet, blocking) for each row of the matrix table."""
    with open(DOC, encoding="utf-8") as handle:
        for line in handle:
            if not line.lstrip().startswith("|"):
                continue
            cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
            if len(cells) != COLUMNS:
                continue
            workflow = cells[0].strip("`")
            if workflow not in WORKFLOWS:
                continue
            yield workflow, cells[1], cells[3].strip("`"), cells[4].strip("`"), cells[7]


def main():
    argparse.ArgumentParser(description=__doc__.splitlines()[0]).parse_args()

    all_jobs = {workflow: list(jobs(workflow)) for workflow in WORKFLOWS}
    matched = {workflow: set() for workflow in WORKFLOWS}
    checked = 0
    failures = 0

    for workflow, leg, preset, triplet, blocking in table_rows():
        checked += 1
        actual = blocking.split()[0].lower() if blocking else ""
        if workflow == "debug.yml":
            expected = "yes" if not any(exp for _, _, _, exp in all_jobs[workflow]) else "no"
            if actual != expected:
                print(f"FAIL docs/ci.md [{workflow}, {leg}]: table says '{blocking}', but no "
                      f"job in {workflow} sets experimental")
                failures += 1
            continue

        matches = [job for job in all_jobs[workflow]
                   if job[1] == preset and job[2] == triplet]
        if len(matches) != 1:
            print(f"FAIL docs/ci.md [{workflow}, {leg}]: {len(matches)} job(s) in {workflow} "
                  f"match preset '{preset}' and triplet '{triplet}'")
            failures += 1
            continue

        name, _, _, experimental = matches[0]
        matched[workflow].add(name)
        expected = "no" if experimental else "yes"
        if actual != expected:
            print(f"FAIL docs/ci.md [{workflow}, {leg}]: table says '{blocking}', but "
                  f"{workflow} job '{name}' "
                  f"{'sets' if experimental else 'does not set'} experimental")
            failures += 1

    # A leg added to a workflow without a table row would never be compared above.
    for workflow in ("ci.yml", "matrix.yml"):
        for name, _, triplet, _ in all_jobs[workflow]:
            if name not in matched[workflow]:
                print(f"FAIL docs/ci.md: {workflow} job '{name}' ({triplet}) has no table row")
                failures += 1

    total = sum(len(group) for group in all_jobs.values())
    print(f"checked {checked} table row(s) against {total} job(s) in "
          f"{len(WORKFLOWS)} workflow(s): {failures} error(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
