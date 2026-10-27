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
            lines = fh.readlines()
        missing = []
        # Paths built with a generator expression or a variable ($<TARGET_FILE:...>,
        # scripts/${_shim}) are resolved later; only literal references are checkable. Neither is a
        # glob, a placeholder in a comment, or anything else that is not meant to name one file:
        # `"${CMAKE_CURRENT_LIST_DIR}/patches/*.patch"` is how the patch list is discovered, and a
        # comment that spells a convention out is prose, not a reference.
        for number, line in enumerate(lines, 1):
            if line.lstrip().startswith("#"):
                continue
            for referenced in re.findall(r'"\$\{CMAKE_CURRENT_LIST_DIR\}/([^"]+)"', line):
                if "${" in referenced:
                    continue
                if any(ch in referenced for ch in "*?[]") or "..." in referenced:
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


def check_port_usage(report, root, ports):
    """`ports/<port>/usage` is installed into the package and read by a consumer.

    It must not name a version. It is shipped *by* the port, so a version written into it is a
    second place that has to be updated on every bump - and it was: the usage of the node port said
    v26.12.0 while the package delivered 26.12.1. The same file must also not describe how to build
    the port; a consumer installing a binary package does not build anything.
    """
    version = re.compile(r"[0-9]+[.][0-9]+[.][0-9]+")
    for port in ports:
        usage = os.path.join(root, "ports", port, "usage")
        # The portfile's own header is the same claim in the same place: it said "build the Node.js
        # v26.12.0 source tree" long after the manifest had moved on. Only the leading comment block
        # is scanned - a later comment recording which version a measurement came from is history.
        header = []
        portfile = os.path.join(root, "ports", port, "portfile.cmake")
        # Only this project's own port. An overlay's header exists to name the two versions it sits
        # between - what it pins and what the registry has - so a version there is the point.
        if port == "node" and os.path.isfile(portfile):
            with open(portfile, "r", encoding="utf-8") as handle:
                for line in handle:
                    if not line.startswith("#") and line.strip():
                        break
                    header.append(line)
        targets = []
        if header:
            targets.append(("ports/%s/portfile.cmake" % port, header, 1))
        if os.path.isfile(usage):
            with open(usage, "r", encoding="utf-8") as handle:
                targets.append(("ports/%s/usage" % port, handle.readlines(), 1))
        for where, lines, first in targets:
            for number, line in enumerate(lines, first):
                match = version.search(line)
                if match:
                    report.error(
                        where,
                        "line %d names the version '%s'. These files are shipped by the port, so a "
                        "version in them is a second place to update on every bump and it has "
                        "already drifted once; the manifest is the only place a version lives."
                        % (number, match.group(0)),
                    )


def check_node_patch_version_in_descriptions(report, root, ports):
    """An overlay description must not name the Node.js *patch* version it was derived from.

    It says "the version Node.js v26 ships" for a reason, and the reason survives a patch bump -
    while the sentence does not: nine descriptions said "v26.12.0" and then "v26.12.1" within two
    weeks, each time because a number had been typed where a major version was meant. The library
    versions beside them are the pin itself and stay.
    """
    pattern = re.compile(r"Node[.]js v[0-9]+[.][0-9]+[.][0-9]+")
    for port in ports:
        manifest = os.path.join(root, "ports", port, "vcpkg.json")
        with open(manifest, "r", encoding="utf-8") as handle:
            description = json.dumps(json.load(handle).get("description", ""))
        for match in pattern.finditer(description):
            report.error(
                "ports/%s/vcpkg.json" % port,
                "the description names '%s'. Say the major version instead - the patch version "
                "drifts on every bump and this sentence is not what pins it." % match.group(0),
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


def check_versions_json(report, root):
    """versions.json has to agree with the files it summarises.

    It is the repository's own record of the three numbers (release date, Node.js version,
    vcpkg release - docs/versioning.md). Every field except `port` is derived from somewhere
    else, so the check is a drift detector: the portfile's source archive hash, the manifest
    version, and the workflows' vcpkg pin all have to be the same values it records.
    """
    path = os.path.join(root, "versions.json")
    if not os.path.isfile(path):
        report.error(
            "versions.json",
            "missing: it records the current Node.js and vcpkg pins (docs/versioning.md)",
        )
        return
    with open(path, "r", encoding="utf-8") as fh:
        try:
            data = json.load(fh)
        except ValueError as exc:
            report.error("versions.json", "is not valid JSON: %s" % exc)
            return

    port = data.get("port") or {}
    node = data.get("node") or {}
    vcpkg = data.get("vcpkg") or {}

    release = str(port.get("version", ""))
    if not re.match(r"^\d{8}(\.\d+)?$", release):
        report.error(
            "versions.json",
            "port.version '%s' is neither YYYYMMDD nor YYYYMMDD.N" % release,
        )
    if not isinstance(port.get("released"), bool):
        report.error("versions.json", "port.released has to be true or false")

    manifest_path = os.path.join(root, "ports", "node", "vcpkg.json")
    if os.path.isfile(manifest_path):
        with open(manifest_path, "r", encoding="utf-8") as fh:
            manifest = json.load(fh)
        if node.get("version") != manifest.get("version"):
            report.error(
                "versions.json",
                "node.version '%s' does not match ports/node/vcpkg.json '%s'"
                % (node.get("version"), manifest.get("version")),
            )
        if port.get("manifest_version") != manifest.get("version"):
            report.error(
                "versions.json",
                "port.manifest_version '%s' does not match ports/node/vcpkg.json '%s'"
                % (port.get("manifest_version"), manifest.get("version")),
            )
        if int(port.get("manifest_port_version", 0)) != int(
            manifest.get("port-version", 0)
        ):
            report.error(
                "versions.json",
                "port.manifest_port_version %s does not match ports/node/vcpkg.json %s"
                % (port.get("manifest_port_version"), manifest.get("port-version", 0)),
            )

    portfile_path = os.path.join(root, "ports", "node", "portfile.cmake")
    if os.path.isfile(portfile_path):
        with open(portfile_path, "r", encoding="utf-8") as fh:
            portfile = fh.read()
        archive = re.search(r"SHA512\s+([0-9a-f]{128})", portfile)
        if not archive:
            report.error(
                "ports/node/portfile.cmake",
                "no SHA512 for the Node.js source archive",
            )
        elif node.get("sha512") != archive.group(1):
            report.error(
                "versions.json",
                "node.sha512 does not match the Node.js archive hash in "
                "ports/node/portfile.cmake (one of them was bumped without the other)",
            )

    workflow_path = os.path.join(root, ".github", "workflows", "build-test.yml")
    if os.path.isfile(workflow_path):
        with open(workflow_path, "r", encoding="utf-8") as fh:
            workflow = fh.read()
        pin = re.search(r"vcpkg-commit:.*?default:\s*([0-9a-f]{40})", workflow, re.S)
        if not pin:
            report.error(
                ".github/workflows/build-test.yml",
                "no default commit under the vcpkg-commit input",
            )
        elif vcpkg.get("commit") != pin.group(1):
            report.error(
                "versions.json",
                "vcpkg.commit does not match the workflows' vcpkg-commit default "
                "(ADR 0003: they move together)",
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
    check_port_usage(report, root, ports)
    check_node_patch_version_in_descriptions(report, root, ports)
    check_versions_json(report, root)

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
