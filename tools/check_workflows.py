#!/usr/bin/env python3
"""Parse-check the shell and the reusable-workflow contracts in .github/.

A workflow file parses as YAML and is accepted by GitHub even when a `run:` block
inside it is not valid shell: the job runs, the step fails immediately with
`syntax error near unexpected token`, and the leg is red for a reason that reads
like a build failure but is a script mistake. That is exactly how the first run
of the multi-configuration matrix failed - every leg had built, configured and
passed its tests, and then the summary step's dangling `else` failed the job.

GitHub is equally quiet about `with:` keys: an input name that does not match the
callee's `on.workflow_call.inputs` is ignored, so a typo silently uses the default
timeout or preset. The dispatch-only probe in PR #125 needed a literal
`timeout-minutes` for exactly this reason.

This tool extracts each `run:` block and hands it to `bash -n`, which parses
without executing, and checks every local `uses: ./.github/workflows/...` against
that workflow's declared inputs. It runs on every push as part of lint, so these
mistakes are caught in seconds rather than after a two-hour build.

Nothing here executes the scripts, and nothing needs a runner: parsing is the
whole point.

The bash is `bash` on PATH, or Git for Windows' install when PATH has none; a
machine with neither gets one sentence naming the requirement instead of a
subprocess traceback.
"""

import argparse
import glob
import os
import shutil
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


def workflow_call_contract(document):
    """Declared inputs of a reusable workflow, and which required ones have no default.

    PyYAML reads an unquoted YAML 1.1 `on:` as the boolean True, hence the fallback.
    """
    if not isinstance(document, dict):
        return set(), set()
    trigger = document.get("on")
    if trigger is None:
        trigger = document.get(True, {})
    if not isinstance(trigger, dict):
        return set(), set()
    call = trigger.get("workflow_call")
    if not isinstance(call, dict):
        return set(), set()
    inputs = call.get("inputs")
    if not isinstance(inputs, dict):
        return set(), set()
    required = {
        name
        for name, spec in inputs.items()
        if isinstance(spec, dict) and spec.get("required") and "default" not in spec
    }
    return set(inputs), required


def find_workflow_calls(node, path):
    """Yield (location, target workflow, with-mapping) for local reusable-workflow calls."""
    if isinstance(node, dict):
        uses = node.get("uses")
        if isinstance(uses, str) and uses.startswith("./.github/workflows/"):
            values = node.get("with")
            yield path, uses[2:], values if isinstance(values, dict) else {}
        for key, value in node.items():
            yield from find_workflow_calls(value, f"{path}.{key}" if path else str(key))
    elif isinstance(node, list):
        for index, item in enumerate(node):
            yield from find_workflow_calls(item, f"{path}[{index}]")


def find_bash(explicit=None):
    """Return (path, error). `explicit` may be a path or a name to look up on PATH."""
    if explicit:
        if os.path.isfile(explicit):
            return explicit, None
        found = shutil.which(explicit)
        if found:
            return found, None
        return None, f"bash not found: {explicit}"

    found = shutil.which("bash")
    if found:
        return found, None
    if os.name == "nt":
        for variable in ("ProgramFiles", "ProgramFiles(x86)"):
            root = os.environ.get(variable)
            if not root:
                continue
            candidate = os.path.join(root, "Git", "bin", "bash.exe")
            if os.path.isfile(candidate):
                return candidate, None
    return None, ("bash not found; install Git for Windows (or add its bin directory to "
                  "PATH), or pass --bash <path>")


def self_check():
    """Drive both ends of find_bash without parsing a workflow."""
    failures = 0
    path, error = find_bash("check-workflows-no-such-bash")
    if path is not None or not error or "not found" not in error:
        print("FAIL self-check: an explicit missing bash was not reported as not found")
        failures += 1
    path, error = find_bash()
    if path is None:
        print("FAIL self-check: no bash on this machine; the parse path cannot run")
        failures += 1
    print(f"self-check: {2 - failures}/2 cases as specified")
    return 1 if failures else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("workflows", nargs="*",
                        help="workflow and action files; default: every .yml under "
                             ".github/workflows/ and every action.yml under .github/actions/")
    parser.add_argument("--bash", metavar="PATH",
                        help="bash executable; default: PATH, then Git for Windows' install")
    parser.add_argument("--self-check", action="store_true",
                        help="check how a missing bash is reported, without parsing workflows")
    args = parser.parse_args()

    if args.self_check:
        return self_check()

    # Composite actions carry `run:` scripts too - more of them than the workflows do - and they were
    # outside this check from the day it was written: prepare alone is ~200 lines of shell. A gate
    # that validates half the shell in `.github/` reads as if it validates all of it.
    files = args.workflows or sorted(
        glob.glob(os.path.join(".github", "workflows", "*.yml"))
        + glob.glob(os.path.join(".github", "actions", "*", "action.yml")))
    # glob() uses the platform separator on Windows, while `uses: ./.github/workflows/x.yml`
    # is always written with forward slashes. Without this the two never compare equal and every
    # local call is silently skipped (measured: "0 local workflow call(s)" on Windows).
    files = [path.replace(os.sep, "/") for path in files]
    if not files:
        print("check_workflows: no workflow files found", file=sys.stderr)
        return 1

    bash, error = find_bash(args.bash)
    if error:
        print(f"check_workflows: {error}", file=sys.stderr)
        return 1

    errors = 0
    checked = 0
    documents = {}
    for file in files:
        try:
            documents[file] = yaml.safe_load(open(file, encoding="utf-8"))
        except (OSError, yaml.YAMLError) as exc:
            print(f"FAIL {file}: cannot read as YAML: {exc}")
            errors += 1
            continue
        for location, script in find_runs(documents[file], file):
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

    # A with: key that the callee did not declare is silently ignored by GitHub, so a typo
    # changes behaviour without any signal at all. Check it against the callee's own document.
    contracts = {path: workflow_call_contract(doc) for path, doc in documents.items()}
    calls = 0
    for file, document in documents.items():
        for location, target, values in find_workflow_calls(document, file):
            if target not in contracts:
                continue  # the callee was not part of this invocation
            calls += 1
            declared, required = contracts[target]
            for key in values:
                if key not in declared:
                    print(f"FAIL {file} [{location}.with]: '{key}' is not an input of {target}")
                    errors += 1
            for key in sorted(required - set(values)):
                print(f"FAIL {file} [{location}.with]: required input '{key}' of {target} "
                      f"is not passed")
                errors += 1

    print(f"checked {checked} run script(s) and {calls} local workflow call(s) across "
          f"{len(files)} workflow file(s): {errors} error(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
