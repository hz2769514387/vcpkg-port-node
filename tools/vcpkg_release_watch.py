#!/usr/bin/env python3
"""Watch for new vcpkg releases and open an issue when this repository has fallen behind.

Why this exists
---------------

`main` tracks the newest vcpkg release (docs/versioning.md): the dependency graph, every
overlay pin and every ABI hash move with it, and ADR 0003 makes the upgrade an explicit
change. Nothing else will tell us when upstream publishes - vcpkg has no Dependabot manager
either - so this watcher does, once a day.

What it compares
----------------

The pin is `vcpkg.release` in `versions.json`; the candidate is GitHub's latest release of
`microsoft/vcpkg`, whose tags are dates (`2026.07.29`). One request per run normally, and a
second one only when something new exists, because the upgrade needs the release's commit -
that is the `vcpkg-commit` value the workflows check out (ADR 0005).

Safety rules it enforces on itself
----------------------------------

- No retry loop and no polling: the workflow runs it on a schedule.
- Writes go through the `gh` CLI, only when this checkout's `origin` is a GitHub repository,
  and only ever to that repository - never anywhere else.
- Without `GH_TOKEN` (or with `--dry-run`) it prints what it would do and writes nothing.
- It never edits `versions.json` or a workflow: the bump is a reviewed change (ADR 0003).

Usage
-----

    python3 tools/vcpkg_release_watch.py                # act when something new exists
    python3 tools/vcpkg_release_watch.py --dry-run      # report only
    python3 tools/vcpkg_release_watch.py --json         # machine-readable summary

Exit status: 0 when nothing new exists or the report was filed, 1 when something new exists
but nothing could be filed (missing token, missing `gh`), 2 on a hard failure (network,
unreadable versions.json, unexpected tag shape, non-GitHub origin).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.request

from release_watch_common import ensure_issue, emit_outputs, fail, github_repo, repo_root

LATEST_URL = "https://api.github.com/repos/microsoft/vcpkg/releases/latest"
COMMIT_URL = "https://api.github.com/repos/microsoft/vcpkg/commits/%s"
VERSIONS_JSON = "versions.json"
TAG_RE = re.compile(r"^(\d{4})\.(\d{2})\.(\d{2})$")


def read_pinned_release(root):
    path = os.path.join(root, VERSIONS_JSON)
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except OSError as exc:
        fail("cannot read %s: %s" % (VERSIONS_JSON, exc))
    except ValueError as exc:
        fail("%s is not valid JSON: %s" % (VERSIONS_JSON, exc))
    release = (data.get("vcpkg") or {}).get("release")
    if not release:
        fail("%s has no vcpkg.release (docs/versioning.md describes the field)" % VERSIONS_JSON)
    if not TAG_RE.match(release):
        fail("%s pins vcpkg %r, which is not a YYYY.MM.DD release tag"
             % (VERSIONS_JSON, release))
    return release


def fetch_json(url, timeout, token=None):
    """One GET. No retries: a transient failure should show up once and be blamed once."""
    headers = {
        "User-Agent": "vcpkg-port-node release watch",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if token:
        headers["Authorization"] = "Bearer %s" % token
    request = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.load(response)
    except Exception as exc:  # urllib raises a small zoo of exception types
        fail("fetching %s failed: %s" % (url, exc))


def tag_key(tag):
    match = TAG_RE.match(tag or "")
    if not match:
        fail("%r is not a vcpkg release tag (YYYY.MM.DD); upstream changed its tag shape"
             % tag)
    return tuple(int(part) for part in match.groups())


def issue_title(latest, pinned):
    return "[release watch] vcpkg %s available (this repository pins %s)" % (latest, pinned)


def render_body(latest, pinned, published, commit, url):
    commit_text = "`%s`" % commit if commit else "unknown (the commits API answered with nothing)"
    return "\n".join([
        "vcpkg **%s** is released and this repository pins **%s**."
        % (latest, pinned),
        "A scheduled check against `%s` found it." % url,
        "",
        "| | |",
        "|---|---|",
        "| Release | %s |" % latest,
        "| Published | %s |" % (published or "unknown"),
        "| Commit | %s |" % commit_text,
        "| Pinned here | %s |" % pinned,
        "",
        "The upgrade is deliberate (ADR 0003, docs/versioning.md) and moves these together:",
        "",
        "1. `versions.json`: `vcpkg.release` and `vcpkg.commit`;",
        "2. `.github/workflows/build-test.yml`: the `vcpkg-commit` default;",
        "3. `docs/decisions/0003-vcpkg-baseline-policy.md`: the baseline the override pins"
        " resolve against;",
        "4. then the full matrix, because every dependency version and every ABI hash moves."
        " Re-examine each overlay pin in `docs/dependency-disposition.md` on the way.",
        "",
        "`python3 tools/version_tree.py` and `python3 tools/check_repo.py` fail if one of the"
        " three places is left behind.",
        "",
        "{generated by tools/vcpkg_release_watch.py}",
    ])


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--dry-run", action="store_true",
                    help="report only; write nothing even when a token is present")
    ap.add_argument("--timeout", type=float, default=30.0, help="HTTP timeout in seconds")
    ap.add_argument("--json", dest="as_json", action="store_true",
                    help="print the finding as JSON instead of prose")
    ap.add_argument("--cwd", default=os.getcwd(), help="any directory inside the repository")
    args = ap.parse_args(argv)

    root = repo_root(args.cwd)
    pinned = read_pinned_release(root)

    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    latest = fetch_json(LATEST_URL, args.timeout, token)
    tag = (latest or {}).get("tag_name") or ""
    published = (latest or {}).get("published_at") or ""

    report = {
        "pinned": pinned,
        "latest": tag,
        "update_available": "false",
    }

    if tag_key(tag) <= tag_key(pinned):
        emit_outputs("vcpkg release watch", report)
        if args.as_json:
            print(json.dumps(report, indent=2))
        else:
            print("%s is the newest vcpkg release; nothing to report." % pinned)
        return 0

    # Something new: the upgrade needs the exact commit the workflows check out, so this is
    # the one run that makes a second request.
    commit = ""
    try:
        commit = (fetch_json(COMMIT_URL % tag, args.timeout, token) or {}).get("sha", "")
    except SystemExit:
        # A missing commit must not lose the finding; the body says it is unknown.
        commit = ""

    report["update_available"] = "true"
    report["commit"] = commit

    title = issue_title(tag, pinned)
    body = render_body(tag, pinned, published, commit, LATEST_URL)
    dry_run = args.dry_run or not token
    if dry_run and not args.dry_run:
        print("no GH_TOKEN / GITHUB_TOKEN in the environment: reporting only.\n")

    try:
        repo = github_repo(root)
    except SystemExit as exc:
        emit_outputs("vcpkg release watch", report)
        raise exc

    result = ensure_issue(repo, title, body, dry_run)
    emit_outputs("vcpkg release watch", report)
    print("vcpkg %s is available (pinned %s): %s" % (tag, pinned, result))
    if args.as_json:
        print(json.dumps(report, indent=2))
    return 0 if "failed" not in result else 1


if __name__ == "__main__":
    raise SystemExit(main())
