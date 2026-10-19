# 8. ICU comes from vcpkg, and is therefore the one dependency not built by clang-cl

- Status: Accepted
- Date: 2026-10-19
- Supersedes: —

## Context

Two defaults collide on this port, and only one of them can win.

Node.js's default is to **vendor** ICU: `tools/icu/icu-generic.gyp` compiles ICU's own sources
through gyp, so on Windows ICU is built by the same compiler as V8 — clang-cl, which
`vcbuild.bat` forces for every version >= 24 ("ClangCL is required because the Node.js version
being compiled is >= 24"). `--with-intl=system-icu` exists, but it is the alternative.

vcpkg's contract is the opposite: a dependency is one package, installed once, and every
consumer of it in a manifest links **the same copy**. Two copies of one library in a single
process is the failure mode this repository exists to prevent — it is what
`docs/overlay-replacements.md` discloses for every overlay, and what
[ADR 0007](0007-toolchain-configuration-and-linkage-policy.md) pins down for linkage.

Measured facts behind the decision:

- 25 ports in this vcpkg baseline depend on `icu` — `harfbuzz`, `boost-locale`, `boost-regex`,
  `duckdb`, `libphonenumber`, `libical`, `cppcms` and others. A consumer that takes this port
  and any one of them has ICU in the process twice if this port vendors its own.
- vcpkg's `icu` port on Windows builds with **autotools** (`vcpkg_make_configure`,
  `--host=x86_64-pc-mingw32`). Run 39234384887 measured `CC='compile clang-cl.exe'` failing
  there before it compiles a single file, and ICU 78 ships no CMake build, so there is no
  second entry point to reach it with clang-cl.
- `docs/build.md` §4.6 records that the vendored `icu-small` fails in bulk under clang-cl in
  this configuration (over a thousand failing targets). That measurement used to be read as a
  problem to solve. It is now read differently: it is the reason *not* to try.

## Decision

**The port passes `--with-intl=system-icu` and takes ICU from vcpkg. This is permanent, and it
is not a compromise to be revisited when it becomes inconvenient.**

Node.js's default yields here, in the same way it already yields for the other fourteen
externalized dependencies: Node.js defaults to vendoring abseil, highway, simdutf, zlib and
the rest, and this port passes `--shared-*` for all of them because that is what makes it a
vcpkg port rather than a Node.js checkout. ICU is the fifteenth.

What this costs, stated plainly:

- ICU is built by **cl.exe**, because vcpkg's `icu` port is autotools and cannot be built by
  clang-cl. It is the single dependency in the graph whose compiler differs from Node.js's.
- The port therefore does **not** achieve one compiler for everything on Windows. Node.js and
  the consumer are clang-cl — that is Node.js's hard requirement and it is not negotiable —
  and vcpkg builds its dependencies, ICU among them, with vcpkg's own default.

Why that difference is acceptable here, and would not be elsewhere: ICU is a C API, and the
part of the ABI that actually has to match — machine type, CRT, exceptions — does match,
because both compilers build against the same triplet. Only the code generator differs. Two
copies of ICU in one process, by contrast, is a defect with no such argument behind it.

## Consequences

- No vendored ICU, ever: it would put a second ICU into any process that also uses one of the
  25 ports above, and that voids the promise this port is built to keep. A small behavioural
  difference from Node.js's default is a much smaller price than a meaningless port.
- No fork of vcpkg's `icu` port to make it clang-cl: the fork would still be autotools, so the
  fork cannot deliver that. A fork to keep cl.exe would only be worth writing if the rest of
  the dependency graph ever moves to clang-cl, at which point ICU is the piece that has to be
  held back on purpose.
- `docs/build.md` §4.6's "bundled ICU fails in bulk" is evidence, not a work item. The work it
  would have justified is declined by this decision.
- If the arm64 crashes ([issue #22](https://github.com/hz2769514387/vcpkg-port-node/issues/22))
  do turn out to come from a compiler difference, the fix is not to unify ICU — ICU has no
  clang-cl path inside vcpkg — but to change what ICU *is* in this port (a different source of
  the library), which would be a new decision with its own evidence.

## Revisit when

vcpkg's `icu` port gains a build path that clang-cl can drive (a CMake build of ICU, or a
Windows build that is not autotools). Until then ICU stays where it is, and the difference in
compilers stays recorded rather than fixed.
