#!/usr/bin/env python3
"""Watch GitHub Actions checks for pull requests or a workflow run, and merge when green.

Why this exists: every change in this repository ends in a CI run that takes between ten
minutes and two and a half hours, and reading it by hand means refreshing a page. The tool
answers one question - "is it done, and what did it say" - and, asked to, merges the pull
requests that came back clean.

Usage
-----

    # one snapshot and exit (what a human usually wants first)
    python3 tools/ci_watch.py --once 60

    # watch until every check has finished, then report
    python3 tools/ci_watch.py 60 63

    # watch, and merge each pull request that ends green and mergeable
    python3 tools/ci_watch.py --merge 60 63

    # a workflow run rather than pull requests
    python3 tools/ci_watch.py --run 41274399478

Exit status: 0 when everything watched ended green (and was merged, when asked), 1 when
something failed or a merge was not possible, 2 when GitHub could not be asked at all.

Notes
-----

- **An empty check list is not "done", it is "not registered yet".** A pull request whose
  checks have not appeared has no checks to be pending, and a watcher that reads that as
  success merges before anything ran.
- Every GitHub call is retried: this connection drops TLS handshakes, and one dropped
  handshake should not end a two-hour wait.
- The repository is read from `origin`, never typed in, and only `origin` is used. Nothing
  here writes anywhere except the pull request it was asked to merge.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime

#: Conclusions that mean the check ran and failed. `NEUTRAL` and `SKIPPED` are successes
#: for this purpose: a skipped job is what the path filter (ADR 0010) produces, and it is
#: the intended answer, not a defect.
FAILED = {
    "FAILURE",
    "CANCELLED",
    "TIMED_OUT",
    "ACTION_REQUIRED",
    "STARTUP_FAILURE",
    "ERROR",
}

#: States that mean "not finished". An empty string is what `statusCheckRollup` reports for
#: a check that is queued but has not started.
RUNNING = {
    "PENDING",
    "QUEUED",
    "IN_PROGRESS",
    "WAITING",
    "REQUESTED",
    "EXPECTED",
    "",
}

POLL_SECONDS = 180


def repo_from_origin():
    """`owner/name` from the `origin` remote, so nothing is hard-coded per machine."""
    try:
        out = subprocess.run(
            ["git", "remote", "get-url", "origin"],
            capture_output=True, text=True, encoding="utf-8", errors="replace"
        )
    except OSError as exc:
        raise SystemExit("git is not available: %s" % exc)
    url = (out.stdout or "").strip()
    if out.returncode != 0 or not url:
        raise SystemExit("no `origin` remote in this checkout; pass --repo OWNER/NAME")
    # git@github.com:owner/name.git  |  https://github.com/owner/name.git
    match = re.search(r"[:/]([^/:]+/[^/]+?)(?:\.git)?$", url)
    if not match:
        raise SystemExit("cannot read owner/name out of the origin URL: %s" % url)
    return match.group(1)


def gh(args, attempts=4):
    """Run one `gh` command, retrying the calls that fail on the network rather than the answer.

    A non-zero exit is a legitimate answer here (a pull request that does not exist), so the
    distinction is made by the caller: this returns (ok, stdout, stderr) instead of raising.
    """
    last = ""
    for attempt in range(attempts):
        proc = subprocess.run(
            ["gh", *args], capture_output=True, text=True,
            encoding="utf-8", errors="replace"
        )
        if proc.returncode == 0:
            return True, proc.stdout, ""
        last = (proc.stderr or proc.stdout or "").strip()
        if attempt + 1 < attempts:
            time.sleep(4 * (attempt + 1))
    return False, "", last


def gh_json(args, attempts=4):
    ok, out, err = gh(args, attempts=attempts)
    if not ok:
        return None, err
    try:
        return json.loads(out), ""
    except ValueError as exc:
        return None, "unreadable JSON from gh: %s" % exc


def normalise(checks):
    """Split a rollup into (failed, running, passed) lists of (name, state, url)."""
    failed, running, passed = [], [], []
    for check in checks:
        state = (check.get("conclusion") or check.get("state") or "").upper()
        entry = (check.get("name") or "?", state, check.get("detailsUrl") or "")
        if state in FAILED:
            failed.append(entry)
        elif state in RUNNING:
            running.append(entry)
        else:
            passed.append(entry)
    return failed, running, passed


def pr_state(number):
    data, err = gh_json([
        "pr", "view", str(number), "--json",
        "state,mergeable,mergeStateStatus,headRefName,statusCheckRollup,title,url",
    ])
    if data is None:
        return None, err
    failed, running, passed = normalise(data.get("statusCheckRollup") or [])
    return {
        "number": number,
        "state": data.get("state"),
        "mergeable": data.get("mergeable"),
        "merge_state": data.get("mergeStateStatus"),
        "branch": data.get("headRefName"),
        "title": data.get("title"),
        "url": data.get("url"),
        "failed": failed,
        "running": running,
        "passed": passed,
        # "no checks registered yet" is not the same as "all checks passed"
        "registered": bool(data.get("statusCheckRollup")),
    }, ""


def run_state(run_id):
    data, err = gh_json([
        "run", "view", str(run_id), "--json",
        "status,conclusion,displayTitle,url,jobs",
    ])
    if data is None:
        return None, err
    jobs = []
    for job in data.get("jobs") or []:
        jobs.append((
            job.get("name") or "?",
            (job.get("conclusion") or job.get("status") or "").upper(),
            job.get("url") or "",
        ))
    failed = [j for j in jobs if j[1] in FAILED]
    running = [j for j in jobs if j[1] in RUNNING]
    passed = [j for j in jobs if j not in failed and j not in running]
    return {
        "run": run_id,
        "state": (data.get("status") or "").upper(),
        "conclusion": (data.get("conclusion") or "").upper(),
        "title": data.get("displayTitle"),
        "url": data.get("url"),
        "failed": failed,
        "running": running,
        "passed": passed,
        "registered": bool(jobs),
    }, ""


def describe(target):
    """One progress line: what is finished, what is running, and nothing else."""
    if "run" in target:
        mark = target["conclusion"] or target["state"] or "?"
        return ("run %s  %-11s  %d passed, %d running, %d failed"
                % (target["run"], mark, len(target["passed"]),
                   len(target["running"]), len(target["failed"])))
    if target["state"] != "OPEN":
        return "PR #%s  %s" % (target["number"], target["state"])
    if not target["registered"]:
        return "PR #%s  checks not registered yet" % target["number"]
    return ("PR #%s  %-10s  %d passed, %d running, %d failed"
            % (target["number"], target["mergeable"] or "?",
               len(target["passed"]), len(target["running"]), len(target["failed"])))


def finished(target):
    if "run" in target:
        return target["state"] == "COMPLETED"
    if target["state"] != "OPEN":
        return True
    return target["registered"] and not target["running"]


def green(target):
    return not target["failed"] and not target["running"]


def report(target, out=sys.stdout):
    """Everything worth saying about one finished target."""
    if "run" in target:
        print("\nrun %s: %s - %s" % (target["run"], target["conclusion"] or target["state"],
                                     target["url"]), file=out)
    else:
        print("\nPR #%s: %s (%s) %s" % (target["number"], target["state"],
                                        target["mergeable"], target["url"]), file=out)
        if target["title"]:
            print("  %s" % target["title"], file=out)
    if target["failed"]:
        print("  failed:", file=out)
        for name, state, url in target["failed"]:
            print("    %-40s %s  %s" % (name, state, url), file=out)
    if target["passed"]:
        names = ", ".join(name for name, _, _ in target["passed"])
        print("  passed: %s" % names, file=out)


def merge(number):
    ok, out, err = gh(["pr", "merge", str(number), "--merge"])
    if ok:
        return True, (out or "merged").strip()
    return False, (err or out or "gh pr merge failed").strip()


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Watch pull request checks or a workflow run, and merge when green.")
    parser.add_argument("numbers", nargs="*", type=int, metavar="PR",
                        help="pull request numbers to watch")
    parser.add_argument("--run", type=int, metavar="ID",
                        help="watch a workflow run instead of pull requests")
    parser.add_argument("--merge", action="store_true",
                        help="merge each pull request that ends green and mergeable")
    parser.add_argument("--once", action="store_true",
                        help="print one snapshot and exit; no waiting, no merging")
    parser.add_argument("--interval", type=int, default=POLL_SECONDS, metavar="SECONDS",
                        help="seconds between polls (default %d)" % POLL_SECONDS)
    parser.add_argument("--timeout-hours", type=float, default=8.0, metavar="HOURS",
                        help="give up after this long (default 8)")
    parser.add_argument("--repo", metavar="OWNER/NAME",
                        help="repository to ask about (default: read from origin)")
    parser.add_argument("--quiet", action="store_true",
                        help="only print state changes and the final report")
    args = parser.parse_args(argv)

    if not args.numbers and args.run is None:
        parser.error("name at least one pull request, or --run")
    if args.numbers and args.run is not None:
        parser.error("pull requests and --run are different questions; pick one")

    # A watcher is read through `tail` or a redirected log, and a redirected stdout is
    # block-buffered: the first progress line sat in the pipe for the whole two-hour wait
    # when this was written. Line buffering is the difference between a log and a memory.
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except AttributeError:
        pass

    if args.repo:
        repo = args.repo
    else:
        repo = repo_from_origin()
    # `gh` resolves the repository from the checkout; --repo makes it explicit and keeps the
    # tool usable from a directory that is not the repository.
    os.environ["GH_REPO"] = repo

    def look(number):
        return pr_state(number)

    def look_run(run_id):
        return run_state(run_id)

    deadline = time.time() + args.timeout_hours * 3600
    targets = {}
    last_line = {}

    while True:
        if args.run is not None:
            target, err = look_run(args.run)
            if target is None:
                print("%s  run %s unreachable: %s" % (stamp(), args.run, err))
                targets.clear()
                if args.once:
                    return 2
                if time.time() > deadline:
                    return 2
                time.sleep(args.interval)
                continue
            targets["run"] = target
            done = finished(target)
        else:
            done = True
            for number in args.numbers:
                target, err = look(number)
                if target is None:
                    print("%s  PR #%s unreachable: %s" % (stamp(), number, err))
                    done = False
                    continue
                targets[number] = target
                line = describe(target)
                if args.once or line != last_line.get(number):
                    print("%s  %s" % (stamp(), line))
                    last_line[number] = line
                if not finished(target):
                    done = False

        if args.run is not None and (args.once or not args.quiet):
            print("%s  %s" % (stamp(), describe(targets["run"])))

        if done or args.once:
            break
        if time.time() > deadline:
            print("%s  still running after %.1f hours; giving up"
                  % (stamp(), args.timeout_hours))
            return 2
        time.sleep(args.interval)

    for key in (["run"] if args.run is not None else args.numbers):
        target = targets.get(key)
        if target is None:
            print("\n%s: never reached" % key)
            return 2
        report(target)

    if args.once:
        return 0 if all(green(t) for t in targets.values()) else 1

    status = 0
    for number in args.numbers:
        target = targets[number]
        if target["state"] != "OPEN":
            continue
        if not green(target):
            print("\nPR #%s is not green; left open" % number)
            status = 1
            continue
        if target["mergeable"] != "MERGEABLE":
            print("\nPR #%s is green but %s; left open" % (number, target["mergeable"]))
            status = 1
            continue
        if not args.merge:
            print("\nPR #%s is green and mergeable (no --merge given)" % number)
            continue
        ok, message = merge(number)
        print("\nPR #%s: %s" % (number, message if ok else "merge failed - %s" % message))
        if not ok:
            status = 1

    if args.run is not None and targets["run"]["conclusion"] != "SUCCESS":
        status = 1
    return status


def stamp():
    return datetime.now().strftime("%H:%M:%S")


if __name__ == "__main__":
    raise SystemExit(main())
