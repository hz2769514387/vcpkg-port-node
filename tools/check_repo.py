#!/usr/bin/env python3
"""Check the tracked files of this repository against its own rules.

The rules are the ones written down in `AGENTS.md` under "Language and file hygiene":
every tracked file is English, LF-only, UTF-8 without a BOM, and ends with a newline. Two
more checks come from invariants inferred from history: every patch a portfile applies has
to exist, and the version in a port's manifest has to be the version the portfile builds.

All of them read the **index**, never the working tree, so the result reflects what would be
committed - the working tree can carry anything (a checked-out build, an editor's backup).

Usage:

    python3 tools/check_repo.py            # from anywhere inside the repository

Exit status: 0 when every check passes, 1 when at least one fails. Failures are printed as
GitHub Actions annotations (`::error::`) so they show up attached to the file in CI.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import unicodedata

#: `.user_local/` is the maintainer's untracked working directory, so it must not be
#: referenced from the files everybody reads. Three files legitimately mention it: the
#: working rules have to point an agent at it, `.gitignore` has to ignore it, and the docs
#: index has to say why nobody can see it, and this tool has to name the rule it checks.
#: Everywhere else it is a portability bug.
USER_LOCAL_REFERENCE_ALLOWED = {
    "AGENTS.md",
    ".gitignore",
    "docs/README.md",
    "tools/check_repo.py",
}

#: CJK Ideographs, Hiragana, Katakana, Hangul, plus CJK punctuation and fullwidth forms.
CJK_RANGES = (
    ("CJK Unified Ideographs", 0x3000, 0x303F),
    ("CJK Unified Ideographs", 0x3040, 0x30FF),
    ("CJK Unified Ideographs Extension", 0x3400, 0x4DBF),
    ("Hangul Syllables", 0xAC00, 0xD7AF),
    ("CJK Unified Ideographs (> BMP)", 0x20000, 0x2FA1F),
    ("FULLWIDTH forms", 0xFF00, 0xFFEF),
)


def run_git(args, cwd):
    proc = subprocess.run(
        ["git", *args], cwd=cwd, capture_output=True, check=False
    )
    if proc.returncode != 0:
        sys.stderr.write("git %s failed:\n%s\n" % (" ".join(args), proc.stderr.decode("utf-8", "replace")))
        raise SystemExit(2)
    return proc.stdout


def repo_root(cwd):
    return run_git(["rev-parse", "--show-toplevel"], cwd=cwd).decode("utf-8").strip()


def tracked_files(cwd):
    """`[(path, blob-sha)]` for every file currently in the index."""
    out = run_git(["ls-files", "-s", "-z"], cwd=cwd).decode("utf-8")
    entries = []
    for record in out.split("\0"):
        if not record:
            continue
        meta, _, path = record.partition("\t")
        fields = meta.split()
        if len(fields) < 2:
            continue
        entries.append((path, fields[1]))
    return entries


def read_blob(sha, cwd):
    return subprocess.run(
        ["git", "cat-file", "blob", sha], cwd=cwd, capture_output=True, check=False
    ).stdout


def cjk_characters(line):
    hits = []
    for ch in line:
        if ord(ch) < 0x3000:
            continue
        if any(lo <= ord(ch) <= hi for _, lo, hi in CJK_RANGES):
            hits.append("%s U+%04X" % (ch, ord(ch)))
    return hits


class Report:
    """Collects problems so one run reports all of them instead of the first one only."""

    def __init__(self):
        self.errors = []
        self.warnings = []
        self.checked = 0

    def error(self, path, message):
        self.errors.append("::error file=%s::%s" % (path, message))

    def warn(self, path, message):
        self.warnings.append("::warning file=%s::%s" % (path, message))


def check_blob(report, path, blob):
    if b"\x00" in blob:
        return  # binary file: only Git cares about its bytes
    report.checked += 1

    if blob.startswith(b"\xef\xbb\xbf"):
        report.error(path, "starts with a UTF-8 BOM; write it without one")
        blob = blob[3:]
    if blob and not blob.endswith(b"\n"):
        report.error(path, "last line has no trailing newline")
    if b"\r" in blob:
        report.error(
            path,
            "contains CR (CRLF line endings); .gitattributes sets text=auto eol=lf, "
            "so normalize before committing",
        )

    text = blob.decode("utf-8", "replace")
    if "\ufffd" in text:
        report.error(path, "is not valid UTF-8")
        return
    allow_user_local = path in USER_LOCAL_REFERENCE_ALLOWED
    for number, line in enumerate(text.splitlines(), start=1):
        hits = cjk_characters(line)
        if hits:
            detail = ", ".join(hits[:5])
            report.error(
                path,
                "line %d has CJK text (tracked files are English): %s" % (number, detail),
            )
        if ".user_local" in line and not allow_user_local:
            report.warn(
                path,
                "line %d references .user_local/, which is untracked and invisible to "
                "everyone else" % number,
            )

    if unicodedata.normalize("NFC", text) != text:
        report.warn(path, "contains non-NFC Unicode sequences")


def check_port_patches(report, root, ports):
    for port in ports:
        portfile = os.path.join(root, "ports", port, "portfile.cmake")
        if not os.path.isfile(portfile):
            report.error("ports/%s/portfile.cmake" % port, "port directory has no portfile.cmake")
            continue
        with open(portfile, "r", encoding="utf-8") as fh:
            content = fh.read()
        missing = []
        # Paths built with a generator expression or a variable ($<TARGET_FILE:...>,
        # scripts/${_shim}) are resolved later; only literal references are checkable.
        for referenced in re.findall(r'"\$\{CMAKE_CURRENT_LIST_DIR\}/([^"]+)"', content):
            if "${" in referenced:
                continue
            if not os.path.isfile(os.path.join(root, "ports", port, referenced)):
                missing.append(referenced)
        for referenced in missing:
            report.error(
                "ports/%s/portfile.cmake" % port,
                "references %s, which does not exist" % referenced,
            )


def check_port_versions(report, root, ports):
    for port in ports:
        manifest_path = os.path.join(root, "ports", port, "vcpkg.json")
        portfile_path = os.path.join(root, "ports", port, "portfile.cmake")
        with open(manifest_path, "r", encoding="utf-8") as fh:
            manifest = json.load(fh)
        version = None
        for key in ("version", "version-string", "version-semver", "version-date"):
            if key in manifest:
                version = manifest[key]
                break
        if not version:
            report.error("ports/%s/vcpkg.json" % port, "has no version field")
            continue
        if not os.path.isfile(portfile_path):
            continue
        with open(portfile_path, "r", encoding="utf-8") as fh:
            content = fh.read()
        if "${VERSION}" in content:
            # Standard vcpkg shape: the portfile builds whatever the manifest declares.
            continue
        if version not in content:
            report.error(
                "ports/%s/portfile.cmake" % port,
                "mentions neither %s nor ${VERSION}; the manifest version and the portfile "
                "drifted apart" % version,
            )


def discover_ports(root):
    ports_dir = os.path.join(root, "ports")
    if not os.path.isdir(ports_dir):
        return []
    return sorted(
        name
        for name in os.listdir(ports_dir)
        if os.path.isfile(os.path.join(ports_dir, name, "vcpkg.json"))
    )


def check_overlay_disclosure(report, root, ports):
    """Every port must be disclosed in docs/overlay-replacements.md.

    An overlay whose name exists in the registry silently replaces that library for
    the consumer's whole dependency graph; the disclosure file is what makes that
    visible before it happens, so a new port without a row is a review blocker.
    Rows are matched by the backticked port name in the first column.
    """
    doc = os.path.join(root, "docs", "overlay-replacements.md")
    if not os.path.isfile(doc):
        report.error(
            "docs/overlay-replacements.md",
            "missing: every port under ports/ has to be disclosed there",
        )
        return
    with open(doc, "r", encoding="utf-8") as fh:
        text = fh.read()
    for port in ports:
        if "| `%s` |" % port not in text:
            report.error(
                "docs/overlay-replacements.md",
                "ports/%s has no row in the disclosure table (say what it replaces and "
                "what changes for a consumer)" % port,
            )


def main(argv=None):
    cwd = os.getcwd()
    root = repo_root(cwd)
    report = Report()

    for path, sha in tracked_files(root):
        check_blob(report, path, read_blob(sha, root))

    ports = discover_ports(root)
    check_port_patches(report, root, ports)
    check_port_versions(report, root, ports)
    check_overlay_disclosure(report, root, ports)

    for line in report.warnings:
        print(line)
    for line in report.errors:
        print(line)

    print(
        "checked %d tracked files and %d ports: %d error(s), %d warning(s)"
        % (report.checked, len(ports), len(report.errors), len(report.warnings))
    )
    return 1 if report.errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
