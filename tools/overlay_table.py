#!/usr/bin/env python3
"""Check that docs/overlay-replacements.md agrees with the ports it describes.

Every directory under `ports/` shadows a registry port for the whole dependency graph, so the table
in `docs/overlay-replacements.md` is a consumer-facing promise: "link this graph and you get these
versions". Nothing enforced it. An overlay could be bumped - as `brotli` was, 1.2.0 to 1.2.1 - and
the table would keep saying the old number until someone noticed, which is exactly the drift that
made a stale claim look like a current one.

This tool reads each port's manifest, extracts the version from its row in the table, and reports
the rows whose two numbers disagree. It checks the version the graph *gets* (the third column), not
the registry version it replaces: that one is prose about someone else's tree, and this repository
cannot keep it true without a vcpkg checkout.

Usage:
    python3 tools/overlay_table.py --check     # exit 1 when a row disagrees with its manifest
    python3 tools/overlay_table.py             # the same report, always exit 0

The table's prose columns ("what changes for you") are not parsed and not generated: a tool cannot
write the sentence that explains why a fork matters, and a generated table would lose it.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TABLE = os.path.join(ROOT, "docs", "overlay-replacements.md")
PORTS = os.path.join(ROOT, "ports")

# | `name` | registry | graph gets | what changes for you |
ROW = re.compile(r"^\|\s*`(?P<name>[a-z0-9][a-z0-9-]*)`\s*\|\s*(?P<registry>[^|]*)\|\s*(?P<graph>[^|]*)\|")

VERSION_KEYS = ("version", "version-semver", "version-date", "version-string")


def port_version(path: str) -> str | None:
    with open(os.path.join(path, "vcpkg.json"), encoding="utf-8") as handle:
        manifest = json.load(handle)
    for key in VERSION_KEYS:
        if key in manifest:
            return str(manifest[key])
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="fail when a row disagrees with its manifest")
    args = parser.parse_args()

    with open(TABLE, encoding="utf-8") as handle:
        rows = {}
        for line in handle:
            match = ROW.match(line)
            if match:
                rows[match.group("name")] = (match.group("registry").strip(), match.group("graph").strip())

    ports = {
        name: port_version(os.path.join(PORTS, name))
        for name in sorted(os.listdir(PORTS))
        if os.path.isfile(os.path.join(PORTS, name, "vcpkg.json"))
    }

    problems = []
    for name, version in ports.items():
        if name not in rows:
            problems.append(f"{name}: no row in the table")
            continue
        registry, graph = rows[name]
        if version is None:
            problems.append(f"{name}: manifest has no version field")
            continue
        # The graph column starts with the version, sometimes emphasised: **1.2.1** or `**3.6.3**`.
        if re.search(rf"(?<![\d.]){re.escape(version)}(?![\d.])", graph) is None:
            problems.append(f"{name}: manifest says {version}, the table's graph column says '{graph[:60]}'")

    for name in rows:
        if name not in ports:
            problems.append(f"{name}: the table has a row but ports/ does not have the port")

    if problems:
        print(f"docs/overlay-replacements.md disagrees with ports/ in {len(problems)} place(s):")
        for problem in problems:
            print(f"  {problem}")
        print("\nThe table is a consumer-facing promise; update the row that moved, not the port.")
        return 1 if args.check else 0

    print(f"ok  {len(ports)} overlays, every row agrees with its manifest")
    return 0


if __name__ == "__main__":
    sys.exit(main())
