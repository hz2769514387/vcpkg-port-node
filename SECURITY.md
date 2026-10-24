# Security policy

## Scope

This repository packages Node.js for vcpkg: the portfile, the patch set, the overlay ports it
ships (zlib, abseil, and the rest — see [docs/overlay-replacements.md](docs/overlay-replacements.md)),
and the CI that verifies them.

Two kinds of report are in scope here:

- **In this repository** — a patch that changes Node.js behaviour in a way that weakens it, an
  overlay port that ships a modified dependency without saying so, a build that silently drops a
  security-relevant feature (ASLR, stack protector, OpenSSL configuration), or a delivered
  configuration that differs from what the documentation claims.
- **Upstream, but reachable through this port** — a vulnerability in Node.js itself, or in a
  dependency vcpkg resolves. Those belong upstream first; tell us as well if the port's
  configuration makes them worse (for example, the OpenSSL build route in ADR 0009).

## How to report

Use GitHub's **private vulnerability reporting** — the repository's *Security* tab, "Report a
vulnerability". It stays private until an advisory is published, and it needs no email address from
either side.

Please do not open a public issue first, and please do not include a working exploit in a pull
request.

## What to expect

- An acknowledgement within a week, from one maintainer doing this in their own time.
- An assessment: which pins are affected (a version tag names all three numbers), and whether the
  fix is a patch in `ports/node/patches/` or an upstream bump.
- A release with the fix, tagged and with its CI run in the body — the process in
  [docs/versioning.md](docs/versioning.md) §4 does not have a fast path, and a security fix does not
  get one either: it goes through the same matrix.

## What this repository does not control

The Node.js source tree, its dependencies, and the vcpkg registry. If a report is only about those,
we will point at the right tracker rather than duplicate the fix here.
