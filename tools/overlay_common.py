#!/usr/bin/env python3
"""The parts `tools/overlay_table.py` and `tools/overlay_report.py` both need.

Both read the same table (`docs/overlay-replacements.md`), the same manifests, and the same
version field order. Each carried its own copy of the row regex and the key tuple, which is two
places to update when the table or a manifest shape changes; this is the one place.

It is a module, not a command: no `main`, no CLI.
"""

from __future__ import annotations

import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PORTS = os.path.join(ROOT, "ports")
TABLE = os.path.join(ROOT, "docs", "overlay-replacements.md")

#: The manifest fields vcpkg accepts as a version, in the order this repository uses them.
VERSION_KEYS = ("version", "version-semver", "version-date", "version-string")

# | `name` | registry | graph gets | what changes for you |
ROW = re.compile(
    r"^\|\s*`(?P<name>[a-z0-9][a-z0-9-]*)`\s*\|\s*(?P<registry>[^|]*)\|\s*(?P<graph>[^|]*)\|"
)


def manifest_version(port_dir):
    """The version a port directory's manifest declares, or None."""
    with open(os.path.join(port_dir, "vcpkg.json"), encoding="utf-8") as handle:
        manifest = json.load(handle)
    for key in VERSION_KEYS:
        if key in manifest:
            return str(manifest[key])
    return None
