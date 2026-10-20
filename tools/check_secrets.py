#!/usr/bin/env python3
"""Scan for credentials that must not reach the public repository.

Two modes:

  --staged   scan the lines staged for the next commit. This is what the
             pre-commit hook (.githooks/, enabled with
             `git config core.hooksPath .githooks`) runs, and it is fast by
             construction: it reads one diff.
  --all      scan every blob in the repository's history. This is what lint.yml
             runs, and it is the audit: a secret that slipped through before
             the hook existed is still a secret in a public clone.

The patterns are deliberately conservative. A scanner that cries wolf on every
`token` word gets disabled within a week; one that misses a private key is
worse than no scanner. What is checked:

  * PEM private keys
  * token formats with provider prefixes (GitHub gh*_..., github_pat_, AWS
    AKIA, Slack xox)
  * credentials inside URLs (scheme://user:password@host)
  * assignments of a literal to a password, secret, token or API key variable, where the value
    is filtered against the shapes that are not secrets: reads from the
    environment, command substitutions, placeholders, examples
  * Authorization: Bearer/Basic/Token headers with a literal value

Anything else - high-entropy strings without an auth keyword, base64 blobs -
is not flagged: this tree carries SHA512 sums, git tree ids and test fixtures
by the thousand, and entropy alone cannot tell them from a leaked password.
"""

import argparse
import re
import subprocess
import sys

# --- patterns ---------------------------------------------------------------

PATTERNS = [
    # name, regex, group index whose value is checked against NOISE (None = keep)
    ("PEM private key",
     re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"), None),
    ("GitHub token",
     re.compile(r"\bgh[pousr]_[A-Za-z0-9]{30,}\b"), None),
    ("GitHub app token",
     re.compile(r"\bgithub_pat_[A-Za-z0-9_]{30,}\b"), None),
    ("AWS access key",
     re.compile(r"\bAKIA[0-9A-Z]{16}\b"), None),
    ("Slack token",
     re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}\b"), None),
    ("credentials in URL",
     re.compile(r"\b[a-z][a-z0-9+.-]*://[^/\s:@\"']{1,64}:([^/\s@\"']{3,})@"), 1),
    ("credential assignment",
     re.compile(r"(?i)\b(?:password|passwd|pwd|secret|token|api[_-]?key|apikey"
                r"|access[_-]?key|private[_-]?key|credential)\b\s*[:=]\s*"
                r"[\"']?([^\s\"']{8,})"), 1),
    ("authorization header",
     re.compile(r"(?i)\b(?:authorization|auth)\b\s*[:=]\s*[\"']?"
                r"(?:bearer|basic|token)\s+([A-Za-z0-9+/=_\-.]{8,})"), 1),
]

# Values that are not secrets: reads from the environment, command or variable
# substitutions, placeholders, documentation examples.
NOISE = re.compile(
    r"^(?:\$\{|\$\(|%[A-Za-z0-9_]+%|\{\{|\$"
    r"|(?i:example|sample|dummy|placeholder|changeme|change-me|redacted"
    r"|your[-_a-z0-9]*|xxx+|test|none|null|true|false|token|secret|password)"
    r")")

# Shapes that are code, not a literal: reading the value from the environment,
# or producing it with a format string. Checked with find over the whole value,
# because these appear after the first character.
NOT_A_LITERAL = re.compile(r'(?i:environ|getenv)|%[sd]|%\(|\.format\(|f[\x22\x27]')

# --- scanning ---------------------------------------------------------------


def scan_text(text):
    """Yield (pattern name, offending line) for every match in text.

    Scanned line by line, on purpose: a credential is a thing on one line. The
    first version scanned whole blobs, and `if token:` at the end of a line
    matched the assignment pattern with the *next* line's `headers[...]` as its
    value - a false positive born of the match crossing a newline.
    """
    for line in text.splitlines():
        stripped = line.strip()
        for name, pattern, value_group in PATTERNS:
            for match in pattern.finditer(line):
                if value_group is not None:
                    value = match.group(value_group) or ""
                    if (NOISE.match(value) or "$" in value or "{" in value
                            or NOT_A_LITERAL.search(value)):
                        continue
                out = stripped if len(stripped) <= 200 else stripped[:200] + "..."
                yield name, out


def scan_staged():
    """Scan the added lines of the index against HEAD."""
    diff = subprocess.run(
        ["git", "diff", "--cached", "-U0", "--no-color"],
        capture_output=True, text=True, encoding="utf-8", errors="replace")
    if diff.returncode != 0:
        print(f"check-secrets: git diff failed: {diff.stderr.strip()}",
              file=sys.stderr)
        return 2
    current_file = None
    findings = 0
    for line in diff.stdout.splitlines():
        if line.startswith("+++ b/"):
            current_file = line[6:]
        elif line.startswith("+") and not line.startswith("+++"):
            for name, offending in scan_text(line[1:]):
                findings += 1
                print(f"check-secrets: {name} staged in {current_file}")
                print(f"    {offending}")
    return 1 if findings else 0


def _iter_history_blobs():
    """Yield (path, text) for every blob reachable from any ref."""
    listing = subprocess.run(
        ["git", "rev-list", "--objects", "--all"],
        capture_output=True, text=True, encoding="utf-8", errors="replace")
    if listing.returncode != 0:
        print(f"check-secrets: git rev-list failed: {listing.stderr.strip()}",
              file=sys.stderr)
        return
    paths = {}
    oids = []
    for line in listing.stdout.splitlines():
        if not line.strip():
            continue
        oid, _, path = line.partition(" ")
        oids.append(oid)
        if path:
            paths[oid] = path
    # One `cat-file --batch` process for the whole history: per-object
    # invocations cost minutes on this repository, the batch costs seconds.
    # subprocess.run rather than hand-fed pipes, because writing all the oids
    # while the answers are still being produced deadlocks once the stdin pipe
    # fills - measured, and the reason the first --all run never returned.
    batch = subprocess.run(
        ["git", "cat-file", "--batch"],
        input=("\n".join(oids) + "\n").encode(),
        capture_output=True)
    if batch.returncode != 0:
        print(f"check-secrets: git cat-file failed: {batch.stderr.decode(errors='replace').strip()}",
              file=sys.stderr)
        return
    out = batch.stdout
    view = memoryview(out)
    pos = 0
    for _ in oids:
        newline = out.find(b"\n", pos)
        if newline < 0:
            break  # malformed stream; scanning a partial history is fine
        header = out[pos:newline].decode("utf-8", "replace").split()
        pos = newline + 1
        if len(header) < 3:
            continue
        # The batch echoes every object with its size, then the body plus a
        # trailing newline - commits and trees included. The body has to be
        # consumed for all of them or the stream desynchronizes.
        size = int(header[2])
        body = view[pos:pos + size].tobytes().decode("utf-8", "replace")
        pos += size + 1  # the trailing newline
        if header[1] != "blob" or size > 512 * 1024:
            continue
        yield paths.get(header[0], "?"), body


def scan_all():
    findings = 0
    for path, text in _iter_history_blobs():
        for name, offending in scan_text(text):
            findings += 1
            print(f"check-secrets: {name} in history, file {path}")
            print(f"    {offending}")
    return 1 if findings else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    scope = parser.add_mutually_exclusive_group(required=True)
    scope.add_argument("--staged", action="store_true",
                       help="scan the index against HEAD (pre-commit)")
    scope.add_argument("--all", action="store_true",
                       help="scan every blob in the history (lint)")
    args = parser.parse_args()
    code = scan_staged() if args.staged else scan_all()
    if code:
        print("check-secrets: remove the value, or if it is genuinely not a "
              "secret, reword it so the scanner stops matching (env read, "
              "placeholder) - do not add an exclusion lightly.",
              file=sys.stderr)
    return code


if __name__ == "__main__":
    sys.exit(main())
