#!/usr/bin/env python3
"""Compare Node.js's vendored copy of a library against the upstream release tarball.

Node.js does not always ship the same bytes as the upstream release it claims: it trims
documentation and tests, adds its own build files, sometimes checks in generated headers,
and sometimes carries a handful of patches on top of the released sources. This tool
answers "what exactly is different" with file sets and content hashes, so the answer can be
quoted in a decision record instead of being remembered.

Usage:

    python3 tools/compare_vendored.py --node <node-src.tar.xz> \\
        --upstream <upstream.tar.gz> --path deps/uv

`--path` is the directory inside the Node.js tarball, for example `deps/uv`,
`deps/ngtcp2/ngtcp2`, `deps/v8/third_party/simdutf`. Both archives keep their top-level
directory; it is stripped before comparison.

Output:

    files: upstream / node          how many files each side has
    content differs                 present on both sides, different sha256
    only in upstream                trimmed by Node.js (docs, tests, CI config)
    only in node                    added by Node.js (gyp/GN files, generated headers)

Only the differing source and header files are listed individually: those are the ones that
change behaviour. A long "only in upstream" list is usually just pruning and is not, by
itself, a risk.

Exit status is 0 when the trees match (file sets and contents), 1 otherwise, so the tool
can be used as a gate once a dependency's expected delta is known.
"""

import argparse
import hashlib
import os
import sys
import tarfile

SOURCE_EXTENSIONS = (
    ".c", ".cc", ".cpp", ".cxx", ".h", ".hh", ".hpp", ".hxx",
    ".S", ".s", ".asm", ".inc", ".rs",
)


def read_tree(archive, subpath="", strip_top_level=True):
    """Map relative path -> sha256 for every regular file in the archive."""
    entries = {}
    prefix = subpath.rstrip("/") + "/" if subpath else ""
    with tarfile.open(archive) as tar:
        members = [m for m in tar.getmembers() if m.isfile()]
        tops = {m.name.split("/")[0] for m in members if "/" in m.name}
        top = next(iter(tops)) if (strip_top_level and len(tops) == 1) else ""
        for member in members:
            name = member.name
            if name.startswith("./"):
                name = name[2:]
            if prefix:
                # Strip the archive's own top-level directory (if any) before matching, so
                # the caller does not have to know whether the archive even has one.
                if top:
                    if not name.startswith(top + "/"):
                        continue
                    name = name[len(top) + 1:]
                if not name.startswith(prefix):
                    continue
                rel = name[len(prefix):]
            else:
                rel = name[len(top) + 1:] if top and name.startswith(top + "/") else name
            if not rel:
                continue
            entries[rel] = hashlib.sha256(tar.extractfile(member).read()).hexdigest()
    return entries


def is_source(path):
    return path.lower().endswith(SOURCE_EXTENSIONS)


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--node", required=True, help="Node.js release tarball")
    parser.add_argument("--upstream", required=True, help="upstream release tarball")
    parser.add_argument("--path", required=True,
                        help="directory inside the Node.js tarball, e.g. deps/uv")
    parser.add_argument("--list-limit", type=int, default=40,
                        help="how many differing paths to print (default 40)")
    args = parser.parse_args()

    if not os.path.isfile(args.node):
        parser.error(f"no such file: {args.node}")
    if not os.path.isfile(args.upstream):
        parser.error(f"no such file: {args.upstream}")

    node = read_tree(args.node, args.path)
    up = read_tree(args.upstream, "")

    differ = sorted(p for p in node.keys() & up.keys() if node[p] != up[p])
    only_up = sorted(set(up) - set(node))
    only_node = sorted(set(node) - set(up))
    differ_sources = [p for p in differ if is_source(p)]
    node_only_sources = [p for p in only_node if is_source(p)]

    print(f"node path     : {args.path}")
    print(f"upstream      : {args.upstream}")
    print(f"files         : upstream={len(up)} node={len(node)}")
    print(f"content differs: {len(differ)}  (source/header: {len(differ_sources)})")
    print(f"only upstream : {len(only_up)}")
    print(f"only node     : {len(only_node)}  (source/header: {len(node_only_sources)})")
    if differ_sources:
        print("differing source/header files:")
        for path in differ_sources[:args.list_limit]:
            print(f"  {path}")
    if node_only_sources:
        print("node-only source/header files:")
        for path in node_only_sources[:args.list_limit]:
            print(f"  {path}")
    if differ and not differ_sources:
        print("content differences are non-source files only: " + ", ".join(differ[:16]))

    return 0 if (not differ and not only_up and not only_node) else 1


if __name__ == "__main__":
    sys.exit(main())
