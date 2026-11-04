# 11. ICU is compiled with clang-cl, so a clang-cl Debug process can format a date

- Status: Accepted
- Date: 2026-11-04
- Supersedes: the consequence of [ADR 0008](0008-icu-comes-from-vcpkg.md) that ICU is "the one
  dependency not built by clang-cl", and the "no change to ICU" consequence of
  [ADR 0009](0009-openssl-is-built-with-clang-cl.md)

## Context

On Windows x64, a **Debug** consumer that links this port aborts the first time it formats a
date (`_CrtIsValidHeapPointer(block)`, inside ICU's `DateFormatSymbols` destructor). The
minimal reproducer is ten lines and links ICU alone - no Node.js, no libnode: built with the
MSVC toolset it works, with the ClangCL toolset against the *same* libraries it aborts
(issue #27, comment 6604741311). So the defect is not "a consumer of libnode" and not ICU's
Debug build: it is **cl.exe-built ICU inside a clang-cl-built process**, found by the Debug CRT.

Node.js builds itself with clang-cl on Windows and every consumer this repository tests is
clang-cl, which leaves ICU as the only library in the process compiled by something else.
ADR 0008 accepted exactly that difference, on the argument that ICU is a C API and machine
type, CRT and exceptions all match. The reproducer says the argument does not hold for the
Debug CRT: the code generator matters too.

## Decision

**The `icu` overlay compiles ICU with clang-cl on every Windows triplet, and the compiler is
chosen in the portfile rather than by the triplet.** A consumer keeps a stock triplet; nothing
about how the port is consumed changes.

Two mechanisms carry that through the autotools flow vcpkg drives (`vcpkg_make_configure`):

- **CC/CXX come from the environment.** vcpkg-make prefers `$ENV{CC}` / `$ENV{CXX}` over the
  compiler it detected - the hook its own comment calls "overwrite settings in custom triplets
  via the environment". On a stock triplet it detected cl.exe, so the portfile names clang-cl;
  on a clang triplet it detected clang-cl already and no override is needed.
- **INCLUDE / LIB / PATH are carried over.** vcpkg loads vcvars for its MSVC triplets only,
  so on a chainloaded clang-cl triplet the make flow starts with an empty environment and
  `link.exe` cannot find `kernel32.lib`. The triplet's toolchain assembles what vcvars would
  have set in its own process; the get-vars run records that environment, and the portfile sets
  it again for the process that starts the shell. Environment variables are the only channel
  that survives the msys shell with paths like `C:/Program Files/...`: a flag carrying them is
  retokenized and shatters, which is why this is not done with `-imsvc` / `-libpath` flags.

`--disable-extras` follows from the same compiler choice: `make all` builds ICU's utility
programs and they do not compile under clang-cl. The delivered static libraries need none of
them. The host build a cross build uses is the exception - it is the one that asks for the
`tools` feature, and it stays on cl.exe so those tools exist.

Two ICU patches ride along, both from Node.js's own tree or forced by clang: the era-fallback
fix in `dtfmtsym.cpp` (`status = oldStatus` → `U_ZERO_ERROR`, dormant with full ICU data) and
an `offsetof` assertion in `locid.cpp` that clang rejects on a non-standard-layout type.

## The whole dependency graph is not moved to clang-cl (yet)

Issue #34 asked the wider question, and the answer this session is: not now, with these
measurements. A `*-clang` triplet was built end to end up to the make-based ports, and
`vcpkg-make` makes four assumptions that clang-cl breaks:

1. it escapes MSVC-frontend flags with `-Xcompiler` / `-Xlinker`, which clang-cl rejects
   outright (ICU works around it with `DISABLE_MSVC_TRANSFORMATIONS`, which is why this port
   passes that flag);
2. it prepends the installed library directory to `LDFLAGS` as `-LIBPATH:`, which libtool
   reads as the GCC `-L` form and rejects ("only absolute run-paths are allowed");
3. it puts compiler directories on PATH but not the assembler's, so a spaced `CCAS` path
   (`libffi` assembles `win64.S`) is split by the shell;
4. it wraps `llvm-lib` in the `ar-lib` script with `ARFLAGS=cr`, which the wrapper cannot use.

None of those is about ICU, and fixing them means an overlay of `vcpkg-make` itself - a port
every consumer's make-based builds go through - or the same workaround in each make-based port
as they appear. On top of that, a chainloaded clang-cl triplet never gets vcvars, so every
consumer who wanted the graph configuration would have to use this repository's triplet and
toolchain instead of a stock one, which is the opposite of what ADR 0007 promises.

The measurement and the work item live in issue #34, which stays open for that decision.

## Consequences

- A Windows Debug consumer can format a date on every triplet, including the stock ones, which
  is what lets `test/cases/externalization` assert it again instead of skipping it (#27).
- ICU is built by the same compiler as Node.js and the consumer. On Windows the only library
  still compiled by cl.exe in the default graph is nothing in the subgraph this port
  externalizes except what a consumer adds itself.
- The ICU build now depends on the LLVM that Visual Studio ships (or a standalone LLVM):
  a Windows machine without the clang-cl component cannot build this port, where it could
  before. Visual Studio 2022 with the C++ Clang tools is already a documented requirement for
  Node.js itself, so this removes no working configuration.
- On a stock triplet ICU is built twice in a way that differs from the registry port's build
  (different compiler), so its binary cache entry is distinct from the registry's. That is the
  point of the overlay and is disclosed in `docs/overlay-replacements.md`.
- `--disable-extras` also drops ICU's `uconv`-style utilities from the installed package, as
  the registry port's Emscripten and UWP branches already do.

## Revisit when

`vcpkg-make` learns to drive a clang-cl triplet (no `-Xcompiler`, `-L` instead of `-LIBPATH:`,
the assembler on PATH, `llvm-ar` or `llvm-lib` without `ar-lib`). That is the work issue #34
records; with it the whole graph can follow the compiler without a per-port overlay, and this
ADR's second half is superseded as a consequence rather than as a decision.
