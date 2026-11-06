#!/usr/bin/env python3
"""Check the tracked files of this repository against its own rules.

The rules are the ones written down in `AGENTS.md` under "Language and file hygiene":
every tracked file is English (one listed exception), LF-only, UTF-8 without a BOM, and ends with a
newline. Two
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
# The one tracked file allowed to be in another language: the Chinese README, because the audience
# that asked for this repository reads it before anything else and a translated front door is ordinary
# practice. The English README stays authoritative and links to it; every other file, including every
# other document, is English (AGENTS.md section 2). A second entry here is a decision, not a
# convenience - the rule is easier to keep with one exception than with a directory of them.
TRANSLATED_FILES = {"README.zh-CN.md"}

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


class Index:
    """The tracked files as the index holds them, not as the working tree has them.

    Every check reads through this, so the run judges what a commit would contain: an edit
    that was never staged is invisible here, exactly as it is invisible to CI. Paths use
    forward slashes, the spelling `git ls-files` prints on every platform.
    """

    def __init__(self, cwd):
        self.cwd = cwd
        self.blobs = dict(tracked_files(cwd))
        self._text = {}

    def text(self, path):
        if path not in self._text:
            self._text[path] = read_blob(self.blobs[path], self.cwd).decode(
                "utf-8", "replace"
            )
        return self._text[path]

    def isfile(self, path):
        return path in self.blobs

    def listdir(self, directory):
        prefix = directory.rstrip("/") + "/"
        names = set()
        for path in self.blobs:
            if path.startswith(prefix):
                names.add(path[len(prefix):].split("/", 1)[0])
        return sorted(names)

    def paths(self):
        return sorted(self.blobs)


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
    allow_cjk = path in TRANSLATED_FILES
    for number, line in enumerate(text.splitlines(), start=1):
        hits = [] if allow_cjk else cjk_characters(line)
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


def patch_argument_names(lines):
    """`[(line, token)]` for the patch files a portfile names in a `PATCHES` argument list.

    vcpkg takes bare names there (`install.patch`, `windows/install-pdbs.patch`), which is how
    every overlay in this repository writes them; the `${CMAKE_CURRENT_LIST_DIR}/...` form the
    other check knows about is the explicit variant. Only the argument list is scanned, so a
    comment that names a patch, and a glob that discovers the set, are not references.
    """
    found = []
    in_list = False
    for number, line in enumerate(lines, 1):
        stripped = line.strip()
        if not in_list:
            if stripped == "PATCHES":
                in_list = True
            continue
        if stripped.startswith(")"):
            in_list = False
            continue
        content = stripped.split("#", 1)[0]
        for token in content.split():
            token = token.strip('"')
            if "${" in token or "$<" in token or "$ENV{" in token:
                continue
            if token.endswith(".patch") or token.endswith(".diff"):
                found.append((number, token))
    return found


def check_port_patches(report, index, ports):
    for port in ports:
        portfile = "ports/%s/portfile.cmake" % port
        if not index.isfile(portfile):
            report.error(portfile, "port directory has no portfile.cmake")
            continue
        lines = index.text(portfile).splitlines()
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
                if not index.isfile("ports/%s/%s" % (port, referenced)):
                    missing.append(referenced)
        for number, token in patch_argument_names(lines):
            if not index.isfile("ports/%s/%s" % (port, token)):
                missing.append(token)
        for referenced in missing:
            report.error(
                portfile,
                "references %s, which does not exist" % referenced,
            )


def check_port_versions(report, index, ports):
    for port in ports:
        manifest_path = "ports/%s/vcpkg.json" % port
        portfile_path = "ports/%s/portfile.cmake" % port
        manifest = json.loads(index.text(manifest_path))
        version = None
        for key in ("version", "version-string", "version-semver", "version-date"):
            if key in manifest:
                version = manifest[key]
                break
        if not version:
            report.error(manifest_path, "has no version field")
            continue
        if not index.isfile(portfile_path):
            continue
        content = index.text(portfile_path)
        if "${VERSION}" in content:
            # Standard vcpkg shape: the portfile builds whatever the manifest declares.
            continue
        if version not in content:
            report.error(
                portfile_path,
                "mentions neither %s nor ${VERSION}; the manifest version and the portfile "
                "drifted apart" % version,
            )


def discover_ports(index):
    return sorted(
        name
        for name in index.listdir("ports")
        if index.isfile("ports/%s/vcpkg.json" % name)
    )


def check_port_usage(report, index, ports):
    """`ports/<port>/usage` is installed into the package and read by a consumer.

    It must not name a version. It is shipped *by* the port, so a version written into it is a
    second place that has to be updated on every bump - and it was: the usage of the node port said
    v26.12.0 while the package delivered 26.12.1. The same file must also not describe how to build
    the port; a consumer installing a binary package does not build anything.
    """
    version = re.compile(r"[0-9]+[.][0-9]+[.][0-9]+")
    for port in ports:
        usage = "ports/%s/usage" % port
        # The portfile's own header is the same claim in the same place: it said "build the Node.js
        # v26.12.0 source tree" long after the manifest had moved on. Only the leading comment block
        # is scanned - a later comment recording which version a measurement came from is history.
        header = []
        portfile = "ports/%s/portfile.cmake" % port
        # Only this project's own port. An overlay's header exists to name the two versions it sits
        # between - what it pins and what the registry has - so a version there is the point.
        if port == "node" and index.isfile(portfile):
            for line in index.text(portfile).splitlines(keepends=True):
                if not line.startswith("#") and line.strip():
                    break
                header.append(line)
        targets = []
        if header:
            targets.append((portfile, header, 1))
        if index.isfile(usage):
            targets.append((usage, index.text(usage).splitlines(keepends=True), 1))
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


def check_node_patch_version_in_descriptions(report, index, ports):
    """An overlay description must not name the Node.js *patch* version it was derived from.

    It says "the version Node.js v26 ships" for a reason, and the reason survives a patch bump -
    while the sentence does not: nine descriptions said "v26.12.0" and then "v26.12.1" within two
    weeks, each time because a number had been typed where a major version was meant. The library
    versions beside them are the pin itself and stay.
    """
    pattern = re.compile(r"Node[.]js v[0-9]+[.][0-9]+[.][0-9]+")
    for port in ports:
        manifest = "ports/%s/vcpkg.json" % port
        description = json.dumps(json.loads(index.text(manifest)).get("description", ""))
        for match in pattern.finditer(description):
            report.error(
                manifest,
                "the description names '%s'. Say the major version instead - the patch version "
                "drifts on every bump and this sentence is not what pins it." % match.group(0),
            )


def check_overlay_disclosure(report, index, ports):
    """Every port must be disclosed in docs/overlay-replacements.md.

    An overlay whose name exists in the registry silently replaces that library for
    the consumer's whole dependency graph; the disclosure file is what makes that
    visible before it happens, so a new port without a row is a review blocker.
    Rows are matched by the backticked port name in the first column.
    """
    doc = "docs/overlay-replacements.md"
    if not index.isfile(doc):
        report.error(
            doc,
            "missing: every port under ports/ has to be disclosed there",
        )
        return
    text = index.text(doc)
    for port in ports:
        if "| `%s` |" % port not in text:
            report.error(
                doc,
                "ports/%s has no row in the disclosure table (say what it replaces and "
                "what changes for a consumer)" % port,
            )


def check_versions_json(report, index):
    """versions.json has to agree with the files it summarises.

    It is the repository's own record of the three numbers (release date, Node.js version,
    vcpkg release - docs/versioning.md). Every field except `port` is derived from somewhere
    else, so the check is a drift detector: the portfile's source archive hash, the manifest
    version, and the workflows' vcpkg pin all have to be the same values it records.
    """
    path = "versions.json"
    if not index.isfile(path):
        report.error(
            path,
            "missing: it records the current Node.js and vcpkg pins (docs/versioning.md)",
        )
        return
    try:
        data = json.loads(index.text(path))
    except ValueError as exc:
        report.error(path, "is not valid JSON: %s" % exc)
        return

    port = data.get("port") or {}
    node = data.get("node") or {}
    vcpkg = data.get("vcpkg") or {}

    release = str(port.get("version", ""))
    if not re.match(r"^\d{8}(\.\d+)?$", release):
        report.error(
            path,
            "port.version '%s' is neither YYYYMMDD nor YYYYMMDD.N" % release,
        )
    if not isinstance(port.get("released"), bool):
        report.error(path, "port.released has to be true or false")

    manifest_path = "ports/node/vcpkg.json"
    if index.isfile(manifest_path):
        manifest = json.loads(index.text(manifest_path))
        if node.get("version") != manifest.get("version"):
            report.error(
                path,
                "node.version '%s' does not match ports/node/vcpkg.json '%s'"
                % (node.get("version"), manifest.get("version")),
            )
        if port.get("manifest_version") != manifest.get("version"):
            report.error(
                path,
                "port.manifest_version '%s' does not match ports/node/vcpkg.json '%s'"
                % (port.get("manifest_version"), manifest.get("version")),
            )
        if int(port.get("manifest_port_version", 0)) != int(
            manifest.get("port-version", 0)
        ):
            report.error(
                path,
                "port.manifest_port_version %s does not match ports/node/vcpkg.json %s"
                % (port.get("manifest_port_version"), manifest.get("port-version", 0)),
            )

    portfile_path = "ports/node/portfile.cmake"
    if index.isfile(portfile_path):
        portfile = index.text(portfile_path)
        archive = re.search(r"SHA512\s+([0-9a-f]{128})", portfile)
        if not archive:
            report.error(
                portfile_path,
                "no SHA512 for the Node.js source archive",
            )
        elif node.get("sha512") != archive.group(1):
            report.error(
                path,
                "node.sha512 does not match the Node.js archive hash in "
                "ports/node/portfile.cmake (one of them was bumped without the other)",
            )

    workflow_path = ".github/workflows/build-test.yml"
    if index.isfile(workflow_path):
        workflow = index.text(workflow_path)
        pin = re.search(r"vcpkg-commit:.*?default:\s*([0-9a-f]{40})", workflow, re.S)
        if not pin:
            report.error(
                workflow_path,
                "no default commit under the vcpkg-commit input",
            )
        elif vcpkg.get("commit") != pin.group(1):
            report.error(
                path,
                "vcpkg.commit does not match the workflows' vcpkg-commit default "
                "(ADR 0003: they move together)",
            )


def check_preset_names(report, index):
    """A preset is named after the triplet it selects, with one documented suffix at most.

    The name is how a reader knows which install a preset consumes, and the test project grew two
    spelling schemes before this rule existed. Only two deviations are legitimate: `-msvc`, a
    `cl.exe` consumer against the same install, and `-debug`, the Debug configuration on a
    generator that fixes it at configure time.
    """
    path = "test/CMakePresets.json"
    if not index.isfile(path):
        return
    try:
        data = json.loads(index.text(path))
    except ValueError as exc:
        report.error(path, "is not valid JSON: %s" % exc)
        return
    suffixes = ("-msvc", "-debug")
    for preset in data.get("configurePresets") or []:
        if preset.get("hidden"):
            continue
        name = preset.get("name", "")
        triplet = (preset.get("cacheVariables") or {}).get("VCPKG_TARGET_TRIPLET")
        if not triplet:
            report.error(
                "test/CMakePresets.json",
                "preset '%s' sets no VCPKG_TARGET_TRIPLET; a preset is named after the triplet "
                "it installs with, so it has to state one" % name,
            )
            continue
        base = name
        for suffix in suffixes:
            if base.endswith(suffix):
                base = base[: -len(suffix)]
                break
        if base != triplet:
            report.error(
                "test/CMakePresets.json",
                "preset '%s' installs '%s'. Name the preset after the triplet, and add at most "
                "one documented suffix ('-msvc', '-debug') for a deliberate deviation."
                % (name, triplet),
            )


def check_triplet_role_markers(report, index):
    """Every triplet this repository carries says, in its first line, that it is a CI cell.

    The files are named exactly like the triplets a consumer may use, and one of them was copied
    into a product build that then failed at configure time on the CRT (issue #61). A marker is
    cheap; a directory name that cannot say it is not.
    """
    directory = "test/cmake/triplets"
    if not index.listdir(directory):
        return
    for name in index.listdir(directory):
        if not name.endswith(".cmake"):
            continue
        path = "%s/%s" % (directory, name)
        first = index.text(path).splitlines()[:1]
        if not first or "CI cell" not in first[0]:
            report.error(
                path,
                "the first line has to say what this file is - a CI cell, not a consumer "
                "recipe. Copying one of these into a product build is the mistake issue #61 "
                "is about.",
            )


def main(argv=None):
    cwd = os.getcwd()
    root = repo_root(cwd)
    report = Report()
    index = Index(root)

    for path in index.paths():
        check_blob(report, path, read_blob(index.blobs[path], root))

    ports = discover_ports(index)
    check_port_patches(report, index, ports)
    check_port_versions(report, index, ports)
    check_overlay_disclosure(report, index, ports)
    check_port_usage(report, index, ports)
    check_node_patch_version_in_descriptions(report, index, ports)
    check_versions_json(report, index)
    check_preset_names(report, index)
    check_triplet_role_markers(report, index)

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
