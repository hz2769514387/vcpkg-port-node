# 13. clang-cl triplets live in this repository, as CI cells with a copyable toolchain

- Status: Accepted
- Date: 2026-11-05
- Supersedes: the sentence in [ADR 0007](0007-toolchain-configuration-and-linkage-policy.md)
  "Every cell is reachable through a triplet that ships with vcpkg, so this repository still
  carries no triplet file of its own", and its claim that every cell it lists is proven in CI.
  ADR 0007's compiler, configuration, linkage and CRT decisions stand.
- Related: [ADR 0012](0012-vcpkg-make-supports-clang-cl.md) makes the graph clang-cl through a
  `vcpkg-make` overlay; this record adds the triplets and the CI cells that exercise it. The
  other half of issue #34.

## Context

ADR 0007 promised that every supported cell is reachable through a stock vcpkg triplet, and
that this repository carries no triplet file. That held while the compiler was not part of the
matrix: the port chose Node.js's compiler, and the dependency graph kept the triplet's MSVC
default.

ADR 0012 changed that. The graph now builds with clang-cl, and vcpkg ships no clang-cl triplet,
so no stock triplet expresses "the same static `/MT` cell, with every dependency built by
clang-cl". The shape that works is not guessable either: a chainloaded toolchain that selects
clang-cl **and includes vcpkg's own `scripts/toolchains/windows.cmake`**, plus
`VCPKG_LOAD_VCVARS_ENV ON`. Without the include, every CMake-based dependency keeps clang-cl's
default `/MD` and a static-CRT graph fails to link; without vcvars, the first try-compile dies
on `kernel32.lib` (both measured; ADR 0012 and [consumer-recipes.md](../consumer-recipes.md) §6).

## Decision

Four triplets in `test/cmake/triplets/`, one per cell: static and `static-md`, x64 and arm64.
Each is a **CI cell** - the first line says so, and `tools/check_repo.py` enforces it - and each
sets `VCPKG_BUILD_TYPE release`. Debug stays where it was: `debug.yml`, on the stock static
triplets.

The chainloaded toolchain is `test/cmake/toolchains/clang-cl.cmake`: a short file, no absolute
paths, and the part a consumer is meant to copy. It selects clang-cl the way vcvars provides it,
adds the target-machine flag, and includes vcpkg's Windows platform file.

The four cells run in `matrix.yml` on every push, blocking, and run Node.js's own suite on the
Release consumer like every other leg. Stock triplets remain the promise: a consumer who never
asks for clang-cl gets today's behaviour, and ICU and OpenSSL keep forcing clang-cl inside their
own portfiles. A consumer's clang-cl triplet is theirs to choose - the community collection
(`walbourn/vcpkg`, branch `clangcltriplets`), this repository's toolchain, or their own file.

## Consequences

- ADR 0007's "carries no triplet file of its own" is false from here on. What replaces it is a
  narrower promise: the repository carries the triplets its own CI needs, and **no triplet here
  is a consumer recipe**.
- `test/cmake/triplets/` grows from six files to ten, and `test/CMakePresets.json` gains four
  configure presets and four build presets. `docs/ci.md`'s matrix table, `test/README.md`'s
  triplet table and both READMEs follow.
- The push gate gains four Windows installs (two x64, two arm64). With a cold cache they are
  four full graph builds, because a new triplet has no archives to restore. That is the cost of
  verifying a dimension no other leg carries; if it becomes the slowest part of the gate, the
  matrix's own rule applies - a cell may move off the blocking set with a reason, never silently.
- Cross builds are out of scope: each cell runs on a machine of its own architecture, and the
  toolchain is written for that.
- The toolchain is an example, not a supported artifact: it has no version, no install rule, and
  no promise to keep working against a consumer's vcpkg.

Not done here: a Debug clang-cl cell, and a clang-cl cell on the dynamic library linkage.
Neither is claimed.
