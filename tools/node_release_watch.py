#!/usr/bin/env python3
"""Watch for new Node.js releases and open an issue when this port has fallen behind.

Why this exists
---------------

Node.js ships patches inside every maintained line, and those patches routinely carry
security fixes, so sitting on a stale patch is not a neutral choice. Nothing else will tell
us: Renovate and Dependabot have no vcpkg manager, and the pinned version lives in
`ports/node/vcpkg.json` plus a SHA512 in the portfile - see ADR 0002.

This tool does one HTTP GET per run against `https://nodejs.org/dist/index.json`, compares
what it finds with the version this repository pins, and then either says nothing is new or
makes sure exactly one open issue describes what is available. It is deliberately the only
place that knows the shape of Node.js's release feed.

Safety rules it enforces on itself
----------------------------------

- One request per run. No retry loop, no polling: the workflow runs it on a schedule.
- Writes go through the `gh` CLI, only when this checkout's `origin` is a GitHub repository,
  and only ever to that repository - never anywhere else.
- Without `GH_TOKEN` (or with `--dry-run`) it prints what it would do and writes nothing.

Usage
-----

    python3 tools/node_release_watch.py                 # act when something new exists
    python3 tools/node_release_watch.py --dry-run       # report only
    python3 tools/node_release_watch.py --json          # machine-readable summary

Exit status: 0 when nothing new exists or the report was filed, 1 when something new exists
but nothing could be filed (missing token, missing `gh`), 2 on a hard failure (network,
unreadable manifest, non-GitHub origin).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.request

INDEX_URL = "https://nodejs.org/dist/index.json"
MANIFEST = "ports/node/vcpkg.json"
ISSUE_LABEL = "dependencies"
VERSION_RE = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)$")


def fail(message, code=2):
    sys.stderr.write("%s\n" % message)
    raise SystemExit(code)


def read_pinned_version(root):
    path = os.path.join(root, MANIFEST)
    try:
        with open(path, "r", encoding="utf-8") as fh:
            manifest = json.load(fh)
    except OSError as exc:
        fail("cannot read %s: %s" % (MANIFEST, exc))
    for key in ("version", "version-string", "version-semver", "version-date"):
        if key in manifest:
            version = manifest[key]
            break
    else:
        fail("%s has no version field" % MANIFEST)
    if not VERSION_RE.match(version):
        fail("%s pins %r, which is not a X.Y.Z version" % (MANIFEST, version))
    return version


def fetch_index(url, timeout):
    """One GET. No retries: a transient failure should show up once and be blamed once."""
    request = urllib.request.Request(
        url, headers={"User-Agent": "vcpkg-port-node release watch", "Accept": "application/json"}
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            payload = json.load(response)
    except Exception as exc:  # urllib raises a small zoo of exception types
        fail("fetching %s failed: %s" % (url, exc))
    return payload


def normalize_version(value):
    """Strip the leading 'v' Node.js uses in its index (`v26.12.0` -> `26.12.0`)."""
    return str(value).strip().lstrip("v")


def parse_versions(payload):
    """Return `[(tuple-of-ints, version-string, lts-name-or-False)]`, newest first."""
    out = []
    for entry in payload:
        version = normalize_version(entry.get("version", ""))
        match = VERSION_RE.match(version)
        if not match:
            continue
        lts = entry.get("lts")
        out.append((tuple(int(part) for part in match.groups()), version, lts or False))
    out.sort(key=lambda item: item[0], reverse=True)
    return out


def classify(pinned, releases):
    """Split the newest release of the pinned line from the newest line overall."""
    pinned_key = tuple(int(part) for part in pinned.split("."))
    same_line = None
    for key, version, lts in releases:
        if key[0] == pinned_key[0]:
            same_line = (key, version, lts)
            break
    newest_line = None
    if releases:
        newest_line = (releases[0][0], releases[0][1], releases[0][2])
    return same_line, newest_line


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
    match = re.match(r"^(?:https://github\.com/|git@github\.com:)([\w.-]+/[\w.-]+?)(?:\.git)?$", url)
    if not match:
        fail("origin is not a GitHub repository: %s (this tool writes nowhere else)" % url, 2)
    return match.group(1)


def issue_title(kind, version, pinned):
    """One stable title per finding, so reruns update the issue instead of duplicating it."""
    pinned_major = pinned.split(".", 1)[0]
    if kind == "same-line":
        return "[release watch] Node.js v%s available (this repository pins v%s)" % (
            version, pinned)
    return "[release watch] Node.js v%s line opened (this repository targets v%s.x)" % (
        version, pinned_major)


def render_body(kind, pinned, finding, extra):
    version, lts, date = finding
    lts_text = "Node.js %s LTS" % lts if lts else "not LTS yet"
    if kind == "same-line":
        headline = (
            "Node.js **v{version}** is published and this repository pins v{pinned}.\n"
            "A scheduled check against `{url}` found it.\n"
        ).format(version=version, pinned=pinned, url=INDEX_URL)
        action = (
            "Bumping inside this line is routine (ADR 0002): update `version` in "
            "`ports/node/vcpkg.json`, the download URL and SHA512 in `ports/node/portfile.cmake`, "
            "rebase `ports/node/patches/`, then run CI across the matrix. Remember to run "
            "`python3 tools/version_tree.py` afterwards - the version files carry the port's "
            "tree hash."
        )
    else:
        headline = (
            "A **new Node.js line** ({version}) exists while this repository targets {pinned}.\n"
            "A scheduled check against `{url}` found it.\n"
        ).format(version=version, pinned=pinned, url=INDEX_URL)
        action = (
            "Crossing a major line is a project, not a version bump (ADR 0002): it gets its own "
            "dependency audit, patch rebase and branch decision. No automatic change is made."
        )
    return "\n".join(
        [
            headline,
            "",
            "| | |",
            "|---|---|",
            "| Version | v%s |" % version,
            "| LTS status | %s |" % lts_text,
            "| Published | %s |" % (date or "unknown"),
            "| Pinned here | v%s |" % pinned,
            "",
            action,
            "",
            "{%s}" % (extra or "generated by tools/node_release_watch.py"),
        ]
    )


def ensure_issue(repo, title, body, dry_run):
    """Create the issue, or rewrite the body if one with this title is already open."""
    if dry_run:
        # Deliberately before any `gh` call: a dry run has to work without credentials, or
        # the lint job that checks this tool every push fails on nothing but a missing token.
        return "would file %r in %s" % (title, repo)

    listed = subprocess.run(
        ["gh", "issue", "list", "--repo", repo, "--state", "open",
         "--limit", "200", "--search", title, "--json", "number,title"],
        capture_output=True, text=True, check=False,
    )
    if listed.returncode != 0:
        return "gh issue list failed: %s" % listed.stderr.strip()
    existing = None
    try:
        for issue in json.loads(listed.stdout or "[]"):
            if issue.get("title") == title:
                existing = issue["number"]
                break
    except json.JSONDecodeError:
        pass

    if dry_run:
        return "would %s issue %r in %s" % (
            "update" if existing else "open", title, repo)

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


def emit_outputs(payload):
    """Feed `$GITHUB_OUTPUT` / `$GITHUB_STEP_SUMMARY` when running inside Actions."""
    output_path = os.environ.get("GITHUB_OUTPUT")
    if output_path:
        with open(output_path, "a", encoding="utf-8") as fh:
            for key, value in payload.items():
                fh.write("%s=%s\n" % (key, value))
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as fh:
            fh.write("### Node.js release watch\n")
            for key, value in payload.items():
                fh.write("- `%s`: %s\n" % (key, value))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--dry-run", action="store_true",
                    help="report only; write nothing even when a token is present")
    ap.add_argument("--timeout", type=float, default=30.0, help="HTTP timeout in seconds")
    ap.add_argument("--json", dest="as_json", action="store_true",
                    help="print the finding as JSON instead of prose")
    ap.add_argument("--cwd", default=os.getcwd(), help="any directory inside the repository")
    args = ap.parse_args(argv)

    root = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=False
    ).stdout.strip() or args.cwd
    pinned = read_pinned_version(root)

    payload = fetch_index(INDEX_URL, args.timeout)
    releases = parse_versions(payload)
    if not releases:
        fail("%s contained no X.Y.Z releases" % INDEX_URL)

    date_by_version = {}
    for entry in payload:
        if isinstance(entry, dict) and entry.get("version"):
            date_by_version[normalize_version(entry["version"])] = entry.get("date") or ""

    same_line, newest_line = classify(pinned, releases)
    pinned_key = tuple(int(part) for part in pinned.split("."))

    findings = []
    if same_line and same_line[0] > pinned_key:
        findings.append((
            "same-line",
            issue_title("same-line", same_line[1], pinned),
            render_body("same-line", pinned,
                        (same_line[1], same_line[2], date_by_version.get(same_line[1])), None),
        ))
    if newest_line and newest_line[0][0] > pinned_key[0]:
        findings.append((
            "new-line",
            issue_title("new-line", newest_line[1], pinned),
            render_body("new-line", pinned,
                        (newest_line[1], newest_line[2], date_by_version.get(newest_line[1])), None),
        ))

    report = {
        "pinned": pinned,
        "latest_in_line": same_line[1] if same_line else "",
        "latest_overall": newest_line[1] if newest_line else "",
        "update_in_line": "true" if any(k == "same-line" for k, _, _ in findings) else "false",
        "new_line_available": "true" if any(k == "new-line" for k, _, _ in findings) else "false",
    }

    if not findings:
        emit_outputs(report)
        if args.as_json:
            print(json.dumps(report, indent=2))
        else:
            print("v%s is the newest release of its line; nothing to report." % pinned)
        return 0

    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    dry_run = args.dry_run or not token
    results = []
    if dry_run and not args.dry_run:
        print("no GH_TOKEN / GITHUB_TOKEN in the environment: reporting only.\n")
    try:
        repo = github_repo(root)
    except SystemExit as exc:
        emit_outputs(report)
        raise exc

    for kind, title, body in findings:
        results.append("%s: %s" % (kind, ensure_issue(repo, title, body, dry_run)))

    for line in results:
        print(line)
        if "failed" in line:
            emit_outputs(report)
            return 1
    emit_outputs(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
