#!/usr/bin/env python3
"""Keep the `git-tree` in the vcpkg version files in sync with `ports/`.

What `git-tree` is
------------------

Every version entry in the vcpkg registry version file `versions/<letter>-/<port>.json`
carries a `git-tree`:

    { "version": "26.12.0", "git-tree": "bd4283f953ad6d282944f01e57f7ee8d52b3b802" }

It is **not** a commit id. It is the Git **tree object hash of the `ports/<port>`
directory** - the fingerprint of every path and every byte inside that directory, exactly
what `git rev-parse HEAD:ports/node` prints. Change one byte under the port directory and
it changes, so the version file has to be regenerated or the recorded version no longer
describes the content.

Why this tool exists
--------------------

Doing it by hand means running `git rev-parse HEAD:ports/<port>` **after** committing, every
single time - and forgetting it once is enough to make the version file lie. This tool does
what vcpkg's own `x-add-version` does, except it works on the **working tree**: the port
directory is staged into a throwaway index and written as a tree, so it can be run before
the commit. As long as what gets committed is what is on disk, the value equals
`git rev-parse HEAD:ports/<port>`.

Determinism
-----------

The temporary index is built with `core.autocrlf=false` and `core.safecrlf=false`, matching
vcpkg upstream, so the hash depends only on the content after `.gitattributes`
normalization - not on whoever ran it, or on which machine.

Usage
-----

    # regenerate the version files for every port under ports/ (run after editing a port)
    python3 tools/version_tree.py

    # verify only - exits 1 when anything is out of date (used by CI)
    python3 tools/version_tree.py --check

    # what would be written, without touching the version files
    python3 tools/version_tree.py --print

Exit status: 0 when everything is consistent (or was written), 1 when `--check` finds a
mismatch, 2 when the environment is wrong (not a Git repository, missing port directory).
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile

REPO_ROOT_HINT = "Run it from inside the repository."


def run_git(args, *, cwd, env=None, check=True):
    """Run one git command and return its stdout as text.

    `check=False` is used where a non-zero exit is an expected answer rather than a
    failure - notably `git rev-parse --verify HEAD` on a branch that has no commit yet.
    """
    proc = subprocess.run(
        ["git", *args],
        cwd=cwd,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    if check and proc.returncode != 0:
        sys.stderr.write(
            "git %s failed (exit %d):\n%s%s\n"
            % (" ".join(args), proc.returncode, proc.stdout, proc.stderr)
        )
        raise SystemExit(2)
    return proc.stdout.strip()


def repo_root(cwd):
    return run_git(["rev-parse", "--show-toplevel"], cwd=cwd)


def compute_git_tree(root, port_rel):
    """Return the tree hash of `port_rel` (a slash-separated path) from the working tree."""
    with tempfile.TemporaryDirectory(prefix="vcpkg-version-tree-") as tmp:
        env = os.environ.copy()
        env["GIT_INDEX_FILE"] = os.path.join(tmp, "index")
        # Match vcpkg upstream: the hash must reflect normalized content only.
        env["GIT_CONFIG_COUNT"] = "2"
        env["GIT_CONFIG_KEY_0"] = "core.autocrlf"
        env["GIT_CONFIG_VALUE_0"] = "false"
        env["GIT_CONFIG_KEY_1"] = "core.safecrlf"
        env["GIT_CONFIG_VALUE_1"] = "false"

        head = run_git(["rev-parse", "--verify", "--quiet", "HEAD"], cwd=root, check=False)
        if head:
            run_git(["read-tree", "HEAD"], cwd=root, env=env)
        else:
            # Unborn branch (no commits yet): start from an empty index.
            run_git(["read-tree", "--empty"], cwd=root, env=env)

        # --force: stage the directory even if some rule would ignore it. Nothing inside a
        # port directory should ever be ignored.
        run_git(["add", "--force", "--", port_rel], cwd=root, env=env)
        root_tree = run_git(["write-tree"], cwd=root, env=env)

        # write-tree gives the tree of the repository root; the version file wants the
        # subtree for the port directory itself.
        return run_git(["rev-parse", "%s:%s" % (root_tree, port_rel)], cwd=root, env=env)


def versions_file(root, versions_root, port):
    """vcpkg layout: versions/<first letter>-/<port>.json, e.g. versions/n-/node.json."""
    return os.path.join(root, versions_root, port[0] + "-", port + ".json")


def load_json(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def wanted_entry(manifest):
    """Build the `{"version": ..., "port-version": ...}` pair from vcpkg.json."""
    for key in ("version", "version-string", "version-semver", "version-date"):
        if key in manifest:
            entry = {"version": manifest[key]}
            if "port-version" in manifest:
                entry["port-version"] = manifest["port-version"]
            return entry
    raise SystemExit(
        "%s has no version / version-string / version-semver / version-date field" % manifest
    )


def same_version(entry, wanted):
    return (
        entry.get("version") == wanted["version"]
        and entry.get("port-version", 0) == wanted.get("port-version", 0)
    )


def discover_ports(ports_root):
    """Every directory under `ports/` that carries a vcpkg.json, sorted by name."""
    if not os.path.isdir(ports_root):
        raise SystemExit("no ports directory: %s\n%s" % (ports_root, REPO_ROOT_HINT))
    ports = [
        name
        for name in os.listdir(ports_root)
        if os.path.isfile(os.path.join(ports_root, name, "vcpkg.json"))
    ]
    if not ports:
        raise SystemExit("no port found under %s\n%s" % (ports_root, REPO_ROOT_HINT))
    return sorted(ports)


def check_port(root, port, tree, vfile, wanted):
    """Return True when the version file already records `tree` for `wanted`."""
    if not os.path.isfile(vfile):
        sys.stderr.write("::error:: missing version file: %s\n" % os.path.relpath(vfile, root))
        return False
    entries = load_json(vfile).get("versions", [])
    matches = [e for e in entries if same_version(e, wanted)]
    if not matches:
        sys.stderr.write(
            "::error:: %s has no entry for version %s\n"
            % (os.path.relpath(vfile, root), wanted["version"])
        )
        return False
    if matches[0].get("git-tree") != tree:
        sys.stderr.write(
            "::error:: git-tree out of date for ports/%s\n"
            "  recorded: %s\n"
            "  actual  : %s\n"
            "  fix     : python3 tools/version_tree.py\n"
            % (port, matches[0].get("git-tree"), tree)
        )
        return False
    return True


def write_port(root, port, tree, vfile, wanted):
    """Insert or update the entry for the port's current version. Returns what changed."""
    entries = load_json(vfile).get("versions", []) if os.path.isfile(vfile) else []
    for e in entries:
        if same_version(e, wanted):
            if e.get("git-tree") == tree:
                return "unchanged"
            e["git-tree"] = tree
            action = "updated"
            break
    else:
        # Newest first, same order as `vcpkg x-add-version` writes.
        entries.insert(0, {**wanted, "git-tree": tree})
        action = "added"

    os.makedirs(os.path.dirname(vfile), exist_ok=True)
    with open(vfile, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(json.dumps({"versions": entries}, indent=2, ensure_ascii=False) + "\n")
    return action


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Generate (or verify) the git-tree in the vcpkg version files."
    )
    ap.add_argument("--port", action="append", default=[], metavar="NAME",
                    help="only this port; repeatable. Default: every port under --ports-root")
    ap.add_argument("--ports-root", default="ports",
                    help="directory holding the ports (default: ports)")
    ap.add_argument("--versions-root", default="versions",
                    help="directory holding the version files (default: versions)")
    ap.add_argument("--check", action="store_true",
                    help="verify only; exit 1 when a version file is missing or out of date")
    ap.add_argument("--print", dest="do_print", action="store_true",
                    help="print one '<port> <git-tree>' line per port and exit")
    ap.add_argument("--cwd", default=os.getcwd(), help="any directory inside the repository")
    args = ap.parse_args(argv)

    root = repo_root(args.cwd)
    ports_root_abs = os.path.join(root, args.ports_root)
    ports = args.port or discover_ports(ports_root_abs)

    failures = []
    for port in ports:
        # Git paths and pathspecs always use forward slashes; os.path.join would give
        # backslashes on Windows and `git rev-parse <tree>:ports\node` fails there.
        port_rel = "/".join(p.strip("/") for p in (args.ports_root, port) if p.strip("/"))
        port_abs = os.path.join(root, *port_rel.split("/"))
        if not os.path.isdir(port_abs):
            raise SystemExit("no such port directory: %s" % port_abs)

        manifest = load_json(os.path.join(port_abs, "vcpkg.json"))
        tree = compute_git_tree(root, port_rel)
        vfile = versions_file(root, args.versions_root, port)
        wanted = wanted_entry(manifest)

        if args.do_print:
            print("%s %s" % (port, tree))
        elif args.check:
            ok = check_port(root, port, tree, vfile, wanted)
            if ok:
                print("ok   %-10s %s" % (port, tree))
            else:
                failures.append(port)
        else:
            rel = os.path.relpath(vfile, root).replace(os.sep, "/")
            print("%-10s %-44s version=%s git-tree=%s"
                  % (write_port(root, port, tree, vfile, wanted), rel,
                     wanted["version"], tree))

    if failures:
        sys.stderr.write(
            "%d port(s) out of date: %s\n" % (len(failures), ", ".join(failures))
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
