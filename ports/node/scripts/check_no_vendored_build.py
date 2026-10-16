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

    python3 check_no_vendored_build.py --build-dir <out/Release>
                                       [--vendored <dir>]... [--except <dir>]...

Exits 0 when no compile step comes from a vendored directory, 1 when one does (naming the file
and the source), 2 on a usage or environment error. `--except` names a subpath that is
legitimately compiled inside a vendored directory - an adapter the embedding project owns,
not the library that was externalized.
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
    "deps/v8/third_party/zlib",
    "deps/zlib",
)

#: Subpaths of a vendored directory that are legitimately compiled even though the library
#: itself is externalized, because the embedding project owns them - an adapter, not the
#: library. V8's `third_party/zlib/google` is Chromium's `compression_utils_portable`, the
#: wrapper V8's own code calls; only the zlib implementation below the wrapper has to be gone.
DEFAULT_VENDORED_EXCEPTIONS = (
    "deps/v8/third_party/zlib/google",
)

#: How a source file appears in gyp's ninja output. The path is relative to the build
#: directory, so it starts two levels up. Three shapes exist:
#:
#:     build x.obj: cxx ..\..\<src>     (a one-line `build` statement)
#:         ..\..\<src>                  (the source on its own continuation line: long command)
#:         cxx ..\..\<src>              (the source still on the rule's line: short command)
#:
#: The last one is not optional. `v8_zlib.ninja` has exactly that shape, so a check that knew
#: only the first two would read straight past the vendored zlib sources it exists to catch.
LEADING_FORMS = (
    "    ../..",
    "    cxx ../..",
    "    cc ../..",
    ": cxx ../..",
    ": cc ../..",
)


def ninja_files(build_dir):
    for root, _dirs, files in os.walk(build_dir):
        for name in files:
            if name.endswith(".ninja"):
                yield os.path.join(root, name)


def native(path):
    return path.replace("/", os.sep).replace("\\", os.sep)


def check(build_dir, vendored, exceptions):
    """Return `[(source, ninja_file, offset)]` for every vendored compile step found.

    Compile steps under an exception subpath are skipped: they are the embedding project's own
    adapter, and the library below them is what was externalized.
    """
    found = []
    scanned = 0
    excluded = tuple(native(e) + os.sep for e in exceptions)
    for ninja in ninja_files(build_dir):
        scanned += 1
        with open(ninja, "r", encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        for directory in vendored:
            native_dir = native(directory)
            for form in LEADING_FORMS:
                needle = native(form) + os.sep + native_dir + os.sep
                start = 0
                while True:
                    offset = text.find(needle, start)
                    if offset == -1:
                        break
                    start = offset + 1
                    name_start = offset + len(needle)
                    name_end = name_start
                    while name_end < len(text) and text[name_end] not in " \t\r\n":
                        name_end += 1
                    source = native_dir + os.sep + text[name_start:name_end]
                    if any(source.startswith(e) for e in excluded):
                        continue
                    found.append((source, ninja, offset))
    return found, scanned


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--build-dir", required=True,
                    help="the gyp build directory, e.g. out/Release")
    ap.add_argument("--vendored", action="append", default=[], metavar="DIR",
                    help="a vendored directory to check; repeatable. Defaults to the set this "
                         "port externalizes.")
    ap.add_argument("--except", action="append", default=[], metavar="DIR",
                    dest="exceptions",
                    help="a subpath of a vendored directory that is legitimately compiled; "
                         "repeatable. Defaults to the adapters this project owns.")
    args = ap.parse_args(argv)

    build_dir = args.build_dir
    if not os.path.isdir(build_dir):
        sys.stderr.write("no such build directory: %s\n" % build_dir)
        return 2

    vendored = args.vendored or list(DEFAULT_VENDORED)
    exceptions = args.exceptions or list(DEFAULT_VENDORED_EXCEPTIONS)
    found, scanned = check(build_dir, vendored, exceptions)

    if not found:
        print("no compile step from a vendored copy (%d ninja files scanned)" % scanned)
        return 0

    for source, ninja, offset in found[:10]:
        sys.stderr.write(
            "externalized library still compiled from the vendored sources:\n"
            "  source: %s\n"
            "  in:     %s (offset %d)\n" % (source, ninja, offset))
    sys.stderr.write(
        "\n%d finding(s). A library this port externalizes is being compiled from the vendored\n"
        "copy as well, so a consumer's process would hold two definitions of its symbols. Find\n"
        "the gyp target that still depends on the vendored copy and gate it on\n"
        "node_shared_<name> - that is what patch 0011 had to do for simdutf.\n" % len(found))
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
