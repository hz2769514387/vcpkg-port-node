#!/usr/bin/env python3
"""Compare this repository's release-only triplets with the stock ones at a vcpkg checkout.

Why this check exists
---------------------

`test/cmake/triplets/` carries hand copies of six stock vcpkg triplets, each adding
`set(VCPKG_BUILD_TYPE release)`, because vcpkg has no release-only twin for those six. The
files say "the stock `X` triplet, Release only", and nothing enforced that sentence: a vcpkg
release that changes a stock triplet - a new setting, a different CRT default - would leave
the CI cells on the old shape while the comment kept claiming otherwise, and `test/README.md`
and `docs/ci.md` describe these files too.

The comparison needs a vcpkg checkout, so it runs at a vcpkg bump (docs/versioning.md §4)
rather than in lint. `docs/ci.md` §2.1 names the six files; the four clang-cl cells are not
in this set - they carry a chainloaded toolchain and are not copies of a stock triplet.

Usage
-----

    python3 tools/check_triplets.py --vcpkg-root /path/to/vcpkg

Exit status: 0 when every carried file matches its stock definition except for
`VCPKG_BUILD_TYPE`, 1 when a field differs (the delta is printed), 2 on a usage or
environment error.
"""

from __future__ import annotations

import argparse
import os
import re
import sys

#: The carried cells that are copies of a stock triplet plus `VCPKG_BUILD_TYPE release`.
#: The name is the stock name with a `-release` suffix; ADR 0013's clang-cl cells are not here
#: because they set a chainloaded toolchain and are not the stock shape.
RELEASE_ONLY = (
    "arm64-windows-release",
    "arm64-windows-static-md-release",
    "x64-linux-dynamic-release",
    "arm64-linux-dynamic-release",
    "x64-osx-dynamic-release",
    "arm64-osx-dynamic-release",
)

SET_LINE = re.compile(r"set\(\s*([A-Za-z0-9_]+)\s+(.*?)\s*\)\s*$")


def settings(path):
    """`{variable: value}` from a triplet's `set(...)` lines; comments are not settings."""
    found = {}
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.split("#", 1)[0].strip()
            match = SET_LINE.match(line)
            if match:
                found[match.group(1)] = match.group(2).strip()
    return found


def stock_path(vcpkg_root, stock):
    for relative in ("triplets", "triplets/community"):
        candidate = os.path.join(vcpkg_root, relative, stock + ".cmake")
        if os.path.isfile(candidate):
            return candidate
    return None


def compare(carried, stock):
    """`[(variable, carried_value, stock_value)]` for every field that may not differ."""
    deltas = []
    for key in sorted(set(carried) | set(stock)):
        if key == "VCPKG_BUILD_TYPE":
            # The one line this repository adds on purpose; it has to be there and be release.
            if carried.get(key) != "release":
                deltas.append((key, carried.get(key, "(absent)"), "release"))
            continue
        if carried.get(key) != stock.get(key):
            deltas.append((key, carried.get(key, "(absent)"), stock.get(key, "(absent)")))
    return deltas


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--vcpkg-root", default=os.environ.get("VCPKG_ROOT"),
                    help="vcpkg checkout at the pin (default: $VCPKG_ROOT)")
    ap.add_argument("--triplets-dir",
                    default=os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                                         "test", "cmake", "triplets"),
                    help="directory holding this repository's carried triplets")
    args = ap.parse_args(argv)

    if not args.vcpkg_root:
        sys.stderr.write("no vcpkg checkout: pass --vcpkg-root or set VCPKG_ROOT\n")
        return 2

    failed = 0
    for name in RELEASE_ONLY:
        carried_path = os.path.join(args.triplets_dir, name + ".cmake")
        if not os.path.isfile(carried_path):
            sys.stderr.write("missing carried triplet: %s\n" % carried_path)
            failed += 1
            continue
        stock_path_ = stock_path(args.vcpkg_root, name[: -len("-release")])
        if not stock_path_:
            sys.stderr.write("stock triplet for %s not found under %s\n"
                             % (name, args.vcpkg_root))
            failed += 1
            continue
        deltas = compare(settings(carried_path), settings(stock_path_))
        if deltas:
            failed += 1
            print("FAIL %s (stock %s)" % (name, os.path.relpath(stock_path_, args.vcpkg_root)))
            for key, got, want in deltas:
                print("  %s: carried %r, stock %r" % (key, got, want))
        else:
            print("ok   %s (VCPKG_BUILD_TYPE release only)" % name)

    if failed:
        print("\n%d carried triplet(s) drifted from the stock definition at the pin. Update the "
              "carried file deliberately, or move the comment's claim with it." % failed)
        return 1
    print("\nevery carried triplet is the stock definition plus VCPKG_BUILD_TYPE release")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
