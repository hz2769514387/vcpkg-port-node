#!/usr/bin/env python3
"""Shared plumbing for the release watchers.

Two watchers exist - `node_release_watch.py` and `vcpkg_release_watch.py` - because the two
upstreams publish in different shapes. What does not differ is the part that talks to this
repository: it writes only to the checkout's own `origin`, only through `gh`, and only when a
token is present. That logic lives here once rather than twice, so the safety rules cannot
drift apart between the two tools.

Nothing in this module fetches anything: each watcher owns its own upstream, including the
"one request per run" discipline.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys

ISSUE_LABEL = "dependencies"


def fail(message, code=2):
    sys.stderr.write("%s\n" % message)
    raise SystemExit(code)


def github_repo(root):
    """Read owner/name from the origin remote, refusing anything that is not GitHub."""
    proc = subprocess.run(
        ["git", "config", "--get", "remote.origin.url"],
        cwd=root,
        capture_output=True,
        text=True,
        check=False,
    )
    url = proc.stdout.strip()
    if not url:
        fail("no 'origin' remote in this checkout", 2)
    match = re.match(
        r"^(?:https://github\.com/|git@github\.com:)([\w.-]+/[\w.-]+?)(?:\.git)?$", url
    )
    if not match:
        fail("origin is not a GitHub repository: %s (this tool writes nowhere else)" % url, 2)
    return match.group(1)


def find_issue(repo, title):
    """Return the number of the open issue with this exact title, or None."""
    listed = subprocess.run(
        ["gh", "issue", "list", "--repo", repo, "--state", "open",
         "--limit", "200", "--search", title, "--json", "number,title"],
        capture_output=True, text=True, check=False,
    )
    if listed.returncode != 0:
        fail("gh issue list failed: %s" % listed.stderr.strip(), 1)
    try:
        for issue in json.loads(listed.stdout or "[]"):
            if issue.get("title") == title:
                return issue["number"]
    except json.JSONDecodeError:
        pass
    return None


def ensure_issue(repo, title, body, dry_run):
    """Create the issue, or rewrite the body if one with this title is already open.

    One stable title per finding means reruns update the issue instead of piling up
    duplicates, which is what makes the watcher safe to run on a schedule.
    """
    if dry_run:
        # Deliberately before any `gh` call: a dry run has to work without credentials, or
        # the lint job that checks these tools every push fails on nothing but a missing token.
        return "would file %r in %s" % (title, repo)

    existing = find_issue(repo, title)
    if existing is not None:
        proc = subprocess.run(
            ["gh", "issue", "edit", str(existing), "--repo", repo, "--body", body],
            capture_output=True, text=True, check=False,
        )
        return "updated issue #%d" % existing if proc.returncode == 0 else (
            "gh issue edit failed: %s" % proc.stderr.strip())

    labelled = subprocess.run(
        ["gh", "issue", "create", "--repo", repo, "--title", title, "--body", body,
         "--label", ISSUE_LABEL],
        capture_output=True, text=True, check=False,
    )
    if labelled.returncode == 0:
        return "opened %s" % (labelled.stdout.strip() or "issue")

    if "label" not in labelled.stderr.lower():
        return "gh issue create failed: %s" % labelled.stderr.strip()

    # A label that does not exist in this repository is not a reason to lose the finding:
    # open the issue without it and say so, so the missing label is visible rather than fatal.
    bare = subprocess.run(
        ["gh", "issue", "create", "--repo", repo, "--title", title, "--body", body],
        capture_output=True, text=True, check=False,
    )
    if bare.returncode != 0:
        return "gh issue create failed: %s" % bare.stderr.strip()
    return "opened %s (without the label %r: create it with 'gh label create %s' if wanted)" % (
        bare.stdout.strip() or "issue", ISSUE_LABEL, ISSUE_LABEL)


def emit_outputs(heading, payload):
    """Feed `$GITHUB_OUTPUT` / `$GITHUB_STEP_SUMMARY` when running inside Actions."""
    output_path = os.environ.get("GITHUB_OUTPUT")
    if output_path:
        with open(output_path, "a", encoding="utf-8") as fh:
            for key, value in payload.items():
                fh.write("%s=%s\n" % (key, value))
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as fh:
            fh.write("### %s\n" % heading)
            for key, value in payload.items():
                fh.write("- `%s`: %s\n" % (key, value))


def repo_root(fallback):
    proc = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True, text=True, check=False,
    )
    return proc.stdout.strip() or fallback
