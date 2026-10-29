#!/usr/bin/env python3
"""Syntax-check every shell script embedded in a workflow.

A workflow file parses as YAML and is accepted by GitHub even when a `run:` block
inside it is not valid shell: the job runs, the step fails immediately with
`syntax error near unexpected token`, and the leg is red for a reason that reads
like a build failure but is a script mistake. That is exactly how the first run
of the multi-configuration matrix failed - every leg had built, configured and
passed its tests, and then the summary step's dangling `else` failed the job.

This tool extracts each `run:` block from every workflow (including the reusable
ones' jobs) and hands it to `bash -n`, which parses without executing. It runs on
every push as part of lint, so a script mistake is caught in seconds rather than
after a two-hour build.

Nothing here executes the scripts, and nothing needs a runner: parsing is the
whole point.
"""

import argparse
import glob
import os
import subprocess
import sys
import tempfile

try:
    import yaml
except ImportError:  # pragma: no cover - lint installs PyYAML
    print("check_workflows: PyYAML is required", file=sys.stderr)
    sys.exit(1)


def find_runs(node, path):
    """Yield (location, script) for every `run:` in a parsed workflow document."""
    if isinstance(node, dict):
        run = node.get("run")
        if isinstance(run, str):
            yield path, run
        for key, value in node.items():
            yield from find_runs(value, f"{path}.{key}" if path else str(key))
    elif isinstance(node, list):
        for index, item in enumerate(node):
            yield from find_runs(item, f"{path}[{index}]")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("workflows", nargs="*",
                        help="workflow and action files; default: every .yml under "
                             ".github/workflows/ and every action.yml under .github/actions/")
    args = parser.parse_args()

    # Composite actions carry `run:` scripts too - more of them than the workflows do - and they were
    # outside this check from the day it was written: prepare alone is ~200 lines of shell. A gate
    # that validates half the shell in `.github/` reads as if it validates all of it.
    files = args.workflows or sorted(
        glob.glob(os.path.join(".github", "workflows", "*.yml"))
        + glob.glob(os.path.join(".github", "actions", "*", "action.yml")))
    if not files:
        print("check_workflows: no workflow files found", file=sys.stderr)
        return 1

    bash = "bash"
    errors = 0
    checked = 0
    for file in files:
        try:
            document = yaml.safe_load(open(file, encoding="utf-8"))
        except (OSError, yaml.YAMLError) as exc:
            print(f"FAIL {file}: cannot read as YAML: {exc}")
            errors += 1
            continue
        for location, script in find_runs(document, file):
            checked += 1
            # bash -n parses without running, which is all we want; the file
            # extension is a hint for the shebang-less script.
            with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False,
                                             encoding="utf-8", newline="\n") as handle:
                handle.write(script)
                temporary = handle.name
            try:
                result = subprocess.run([bash, "-n", temporary],
                                        capture_output=True, text=True)
            finally:
                os.unlink(temporary)
            if result.returncode != 0:
                print(f"FAIL {file} [{location}]: {result.stderr.strip()}")
                errors += 1

    print(f"checked {checked} run script(s) across {len(files)} workflow file(s): "
          f"{errors} error(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
