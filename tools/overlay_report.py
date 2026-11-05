#!/usr/bin/env python3
"""Report how every overlay compares with the registry and with what Node.js vendors.

`docs/overlay-replacements.md` answers "what does the graph get instead of the registry
port". It does not answer the question a consumer of this repository actually asks next:
*is the overlay older than what Node.js itself links?* That answer needs three numbers per
overlay - its own version, the registry's at the pinned vcpkg release, and the version of
the same library inside the Node.js source tree - and only the first one is in this
repository's manifests. The other two are in a checkout and a tarball, so they are recorded
in `docs/overlay-versions.json` and kept true by this tool.

The rule, from issue #77:

    An overlay *behind* the registry is not a defect - simdutf is deliberately the version
    V8 vendors, openssl is the version the baseline ships because its overlay exists for
    the compiler. The defect is being behind **both** - older than the registry and older
    than what Node.js vendors - with no exception written down.

So `--check` fails on that one condition, and reports the rest without judging it.

Usage:
    python3 tools/overlay_report.py                 # print the table, always exit 0
    python3 tools/overlay_report.py --check         # exit 1 on a defect or stale data
    python3 tools/overlay_report.py --refresh-registry [--vcpkg-root DIR]
                                                    # rewrite the registry column from a
                                                    # vcpkg checkout at the pinned release

Everything here is offline: the registry and vendored columns are checked in, because lint
runs on a machine with no vcpkg checkout and downloading the Node.js tarball in lint is
what issue #77 rules out. `--refresh-registry` is the one mode that needs a checkout, and
it is a maintainer command run at a vcpkg bump, not a lint step.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PORTS = os.path.join(ROOT, "ports")
DATA = os.path.join(ROOT, "docs", "overlay-versions.json")
TABLE = os.path.join(ROOT, "docs", "overlay-replacements.md")
VERSIONS = os.path.join(ROOT, "versions.json")

VERSION_KEYS = ("version", "version-semver", "version-date", "version-string")

# | `name` | registry | graph gets | what changes for you |
ROW = re.compile(r"^\|\s*`(?P<name>[a-z0-9][a-z0-9-]*)`\s*\|\s*(?P<registry>[^|]*)\|\s*(?P<graph>[^|]*)\|")

# "not in the registry" is the only cell that is prose rather than a version.
NOT_IN_REGISTRY = re.compile(r"not in the registry", re.IGNORECASE)


def load_json(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def manifest_version(port_dir):
    manifest = load_json(os.path.join(port_dir, "vcpkg.json"))
    for key in VERSION_KEYS:
        if key in manifest:
            return str(manifest[key])
    return None


def overlay_versions():
    return {
        name: manifest_version(os.path.join(PORTS, name))
        for name in sorted(os.listdir(PORTS))
        if os.path.isfile(os.path.join(PORTS, name, "vcpkg.json"))
    }


def version_key(value):
    """A sort key for the version shapes in this graph, or None when it cannot be read.

    Only the numeric prefix counts (`1.3.2.1-motley` and `1.3.2.1` are the same version -
    the suffix names the fork, not a pre-release), numeric segments compare as numbers
    (`1.10 > 1.9`), and a longer numeric prefix wins (`1.3.2.1 > 1.3.2`). Anything with no
    leading number - a commit id, `unknown` - returns None and the comparison is skipped
    rather than guessed.
    """
    if not value:
        return None
    match = re.match(r"^(\d+(?:[.\-_]\d+)*)", value.strip().lstrip("vV"))
    if not match:
        return None
    return [int(part) for part in re.split(r"[.\-_]", match.group(1)) if part]


def compare(overlay, reference):
    """`same`, `ahead`, `behind`, or None when either side cannot be read."""
    left, right = version_key(overlay), version_key(reference)
    if left is None or right is None:
        return None
    # A missing segment is zero, so 1.3.2 and 1.3.2.0 are equal and 1.3.2.1 is greater.
    for index in range(max(len(left), len(right))):
        a = left[index] if index < len(left) else 0
        b = right[index] if index < len(right) else 0
        if a == b:
            continue
        return "ahead" if a > b else "behind"
    return "same"


def verdict(overlay, registry, vendored):
    if registry is None:
        return "not in the registry"
    to_registry = compare(overlay, registry)
    to_vendored = compare(overlay, vendored) if vendored else None
    if to_registry is None:
        return "unknown"
    if to_registry == "behind" and to_vendored == "behind":
        return "behind (both)"
    if to_registry == "behind":
        return "behind (registry)"
    if to_vendored == "behind":
        return "behind (vendored)"
    if to_registry == "same" and to_vendored in (None, "same"):
        return "same"
    return "ahead"


def table_rows():
    with open(TABLE, encoding="utf-8") as handle:
        rows = {}
        for line in handle:
            match = ROW.match(line)
            if match:
                rows[match.group("name")] = match.group("registry").strip()
    return rows


def pinned(path):
    return load_json(path)


def refresh_registry(data, vcpkg_root):
    """Rewrite the registry column from a checkout of the pinned vcpkg release."""
    for name, entry in data["ports"].items():
        if name == "node":
            continue
        manifest = os.path.join(vcpkg_root, "ports", name, "vcpkg.json")
        if not os.path.isfile(manifest):
            entry["registry"] = None
            print(f"  {name}: not in the registry at {vcpkg_root}")
            continue
        version = manifest_version(os.path.join(vcpkg_root, "ports", name))
        entry["registry"] = version
        print(f"  {name}: {version}")
    with open(DATA, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def check(data, versions):
    problems = []

    pin = data.get("vcpkg") or {}
    if pin.get("release") != versions.get("vcpkg", {}).get("release") or pin.get("commit") != versions.get("vcpkg", {}).get("commit"):
        problems.append(
            "docs/overlay-versions.json records vcpkg %s (%s), versions.json records %s (%s) - "
            "refresh the registry column at the new pin"
            % (pin.get("release"), pin.get("commit"), versions.get("vcpkg", {}).get("release"), versions.get("vcpkg", {}).get("commit"))
        )
    if data.get("node", {}).get("version") != versions.get("node", {}).get("version"):
        problems.append(
            "docs/overlay-versions.json records Node.js %s, versions.json records %s - re-read the "
            "vendored versions from the new tarball"
            % (data.get("node", {}).get("version"), versions.get("node", {}).get("version"))
        )

    ports = overlay_versions()
    recorded = data.get("ports") or {}
    for name in ports:
        if name not in recorded:
            problems.append(f"{name}: no row in docs/overlay-versions.json")
    for name in recorded:
        if name not in ports:
            problems.append(f"{name}: recorded, but ports/ has no such port")

    docs_rows = table_rows()
    for name in ports:
        entry = recorded.get(name) or {}
        registry = entry.get("registry")
        if registry is None:
            continue
        if name not in docs_rows:
            problems.append(f"{name}: no row in docs/overlay-replacements.md")
            continue
        cell = docs_rows[name]
        if not re.search(rf"(?<![\d.]){re.escape(registry)}(?![\d.])", cell):
            problems.append(
                f"{name}: the registry column of docs/overlay-replacements.md says '{cell[:40]}', "
                f"the pin says {registry}"
            )
        if NOT_IN_REGISTRY.search(cell):
            problems.append(
                f"{name}: the registry column says 'not in the registry' but vcpkg's port exists at {registry}"
            )

    for name, entry in recorded.items():
        if name not in ports:
            continue
        overlay = ports[name]
        registry = entry.get("registry")
        vendored = entry.get("vendored")
        if vendored is not None and not entry.get("vendored_source"):
            problems.append(f"{name}: vendored version without a vendored_source path")
        if verdict(overlay, registry, vendored) == "behind (both)" and not entry.get("exception"):
            problems.append(
                f"{name}: {overlay} is behind the registry ({registry}) and behind what Node.js "
                f"vendors ({vendored}) - move the overlay forward, or record the reason in its "
                f"exception field"
            )

    return problems


def main(argv=None):
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--check", action="store_true", help="fail on a defect or stale data")
    parser.add_argument("--refresh-registry", action="store_true",
                        help="rewrite the registry column from a vcpkg checkout")
    parser.add_argument("--vcpkg-root", default=os.environ.get("VCPKG_ROOT", ""),
                        help="vcpkg checkout (default: $VCPKG_ROOT)")
    parser.add_argument("--data", default=DATA, help="the recorded data file")
    args = parser.parse_args(argv)

    data = load_json(args.data)

    if args.refresh_registry:
        root = args.vcpkg_root
        if not root or not os.path.isdir(os.path.join(root, "ports")):
            print("--refresh-registry needs a vcpkg checkout: pass --vcpkg-root or set VCPKG_ROOT",
                  file=sys.stderr)
            return 2
        print(f"reading the registry from {root}")
        refresh_registry(data, root)
        return 0

    ports = overlay_versions()
    recorded = data.get("ports") or {}

    width_name = max(len(name) for name in ports) + 2
    print(f"{'port':<{width_name}}{'overlay':<12}{'registry':<12}{'vendored':<22}verdict")
    for name in sorted(ports):
        entry = recorded.get(name) or {}
        registry = entry.get("registry")
        vendored = entry.get("vendored")
        print(
            f"{name:<{width_name}}{ports[name] or '-':<12}{registry or '-':<12}"
            f"{(vendored or 'unknown'):<22}{verdict(ports[name], registry, vendored)}"
        )

    if not args.check:
        return 0

    problems = check(data, pinned(VERSIONS))
    if problems:
        print(f"\noverlay drift: {len(problems)} problem(s)")
        for problem in problems:
            print(f"  {problem}")
        print("\nThe rule is issue #77: only 'behind the registry and behind the vendored copy' "
              "is a defect. Update the row, or record the exception.")
        return 1

    print(f"\nok  {len(ports)} overlays, no overlay is behind both the pin and the Node.js tree")
    return 0


if __name__ == "__main__":
    sys.exit(main())
