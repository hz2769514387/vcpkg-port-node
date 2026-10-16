#!/usr/bin/env python3
"""Fail the build if a library this port externalizes is also compiled from the vendored copy.

Why this check exists
---------------------

`--shared-<name>` is what makes a consumer's process contain one copy of a library instead of
two. It works by removing a dependency edge in the gyp graph - but a target that pulls the
vendored gyp in unconditionally still compiles it. That is not hypothetical: `simdutf.gyp` was
reached through `ada.gyp` regardless of `node_shared_simdutf`, which is why the patch set
carries a fix for it.

Nothing downstream reports the result. The linker silently picks one definition, the process
runs, and the duplicate only shows up later as an ODR violation or as a puzzle about which
version of a library a symbol came from. The build graph, on the other hand, is exact and
cheap to read: gyp's ninja output states every source it compiles.

Usage
-----

    python3 check_no_vendored_build.py --build-dir <out/Release> [--vendored <dir>]...

Exits 0 when no compile step comes from a vendored directory, 1 when one does (naming the file
and the source), 2 on a usage or environment error.
"""

from __future__ import annotations

import argparse
import os
import sys

#: Directories whose contents must not be compiled when the library they hold is externalized.
DEFAULT_VENDORED = (
    "deps/v8/third_party/abseil-cpp",
    "deps/v8/third_party/highway",
    "deps/v8/third_party/simdutf",
    "deps/zlib",
)

#: How a source file appears in gyp's ninja output: a continuation line indented by four
#: spaces, holding a path relative to the build directory. The same-line forms are checked too,
#: for the case where a path is short enough to fit on the `build ...: cxx` line.
LEADING_FORMS = ("    ../..", ": cxx ../..", ": cc ../..")


def ninja_files(build_dir):
    for root, _dirs, files in os.walk(build_dir):
        for name in files:
            if name.endswith(".ninja"):
                yield os.path.join(root, name)


def check(build_dir, vendored):
    """Return `[(needle, ninja_file, offset)]` for every vendored compile step found."""
    found = []
    scanned = 0
    for ninja in ninja_files(build_dir):
        scanned += 1
        with open(ninja, "r", encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        for directory in vendored:
            native = directory.replace("/", os.sep).replace("\\", os.sep)
            for form in LEADING_FORMS:
                needle = form.replace("/", os.sep) + os.sep + native + os.sep
                offset = text.find(needle)
                if offset != -1:
                    found.append((needle, ninja, offset))
    return found, scanned


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--build-dir", required=True,
                    help="the gyp build directory, e.g. out/Release")
    ap.add_argument("--vendored", action="append", default=[], metavar="DIR",
                    help="a vendored directory to check; repeatable. Defaults to the set this "
                         "port externalizes.")
    args = ap.parse_args(argv)

    build_dir = args.build_dir
    if not os.path.isdir(build_dir):
        sys.stderr.write("no such build directory: %s\n" % build_dir)
        return 2

    vendored = args.vendored or list(DEFAULT_VENDORED)
    found, scanned = check(build_dir, vendored)

    if not found:
        print("no compile step from a vendored copy (%d ninja files scanned)" % scanned)
        return 0

    for needle, ninja, offset in found[:10]:
        sys.stderr.write(
            "externalized library still compiled from the vendored sources:\n"
            "  source pattern: %s\n"
            "  in:             %s (offset %d)\n" % (needle, ninja, offset))
    sys.stderr.write(
        "\n%d finding(s). A library this port externalizes is being compiled from the vendored\n"
        "copy as well, so a consumer's process would hold two definitions of its symbols. Find\n"
        "the gyp target that still depends on the vendored copy and gate it on\n"
        "node_shared_<name> - that is what patch 0011 had to do for simdutf.\n" % len(found))
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
