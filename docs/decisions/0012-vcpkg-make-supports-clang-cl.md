# 12. The make flow drives a clang-cl triplet, through an overlay of `vcpkg-make`

- Status: Accepted
- Date: 2026-11-04
- Supersedes: the section *"The whole dependency graph is not moved to clang-cl (yet)"* and the
  *"Revisit when"* paragraph of [ADR 0011](0011-icu-is-built-with-clang-cl.md). ADR 0011's ICU
  decision itself stands.
- Resolves: the blocking half of issue #34. The triplets and the CI cell remain a separate change.

## Context

Issue #34 asked whether the Windows dependency graph should be built with the compiler Node.js
requires. ADR 0011 answered "not yet" and named the blocker: `vcpkg-make`, the helper port every
autotools-based dependency of this graph runs through, encodes cl.exe assumptions behind
`CMAKE_C_COMPILER_FRONTEND_VARIANT STREQUAL "MSVC"`, a condition clang-cl also satisfies.

Measured on libffi (the only libtool-based port in the graph), **two** of those assumptions are
real, and both are in `vcpkg_make_common.cmake`:

1. The assembler is not in the list of programs whose spaced directory is moved onto `PATH`, so
   `CCAS` keeps `C:/Program Files/.../clang-cl.exe` and the msys shell splits it: libffi's
   `src/x86/win64.lo` step dies with `./libtool: line 1938: C:/Program: No such file or directory`.
2. `CMAKE_AR` is `llvm-lib.exe`, wrapped as `AR='ar-lib llvm-lib.exe'` with `ARFLAGS=cr`; ar-lib
   passes its trailing arguments through as a command, so every archive step answers
   `./libtool: line 150: cr: command not found`. The registry's own comment already says the tool
   for this job is llvm-ar, unwrapped - it just does not recognise `llvm-lib`. llvm-ar also
   rejects lib.exe's static-linker flags (`/machine:x64`): it prints its help and exits 0 without
   writing an archive (measured with LLVM 19.1.5).

The third thing ADR 0011 listed - a chainloaded clang-cl triplet arriving without `INCLUDE`,
`LIB` and the MSVC/SDK `bin` directories - **is not a vcpkg-make gap at all**. It is a property
of the triplet: vcpkg's own `VCPKG_LOAD_VCVARS_ENV ON` makes it load vcvars for a non-MSVC
triplet, and the community clang-cl triplets do exactly that
(`walbourn/vcpkg`, branch `clangcltriplets`, `triplets/community/x64-clangcl-*.cmake`: a
`VCPKG_CHAINLOAD_TOOLCHAIN_FILE` that selects clang-cl, plus `VCPKG_LOAD_VCVARS_ENV ON` and
`VCPKG_PLATFORM_TOOLSET ClangCL`). Measured: with that triplet the unmodified registry
`vcpkg-make` gets through configuration and fails on exactly items 1 and 2; without it, the first
try-compile dies earlier with `LNK1181: cannot open input file 'kernel32.lib'`.

Two more items ADR 0011 listed are **not** gaps, and their absence shapes the decision:

- **`-Xcompiler` / `-Xlinker`.** They are a libtool guard, not a compiler spelling: libtool strips
  them before the compiler sees them, and clang-cl ignores them where they do leak through -
  configure runs without libtool and warns "unknown argument ignored" while keeping the option
  that follows (measured; `-Xcompiler -DHELLO` still defines `HELLO`). Removing them is what
  *breaks* a clang-cl build: a Debug configuration's `-RTC1` then reaches libtool's own option
  parser as `-R TC1` and the link dies with "only absolute run-paths are allowed" (measured on
  libffi's Debug link).
- **`-LIBPATH:`** prepended to `LDFLAGS`. With the escaping in place it is passed through to
  link.exe, which accepts the dash spelling; it only breaks when escaping is off, which is what
  the ICU workaround does with `DISABLE_MSVC_TRANSFORMATIONS`.

## Decision

**`ports/vcpkg-make` is an overlay of the registry's `vcpkg-make`, version `2026-07-09` with
`port-version` 2, carrying the two fixes above.** The registry port's manifest, wrapper scripts,
`configure.ac`, `vcpkg_make.cmake` and the other helpers are copied unchanged; the portfile
differs only in naming its two wrapper files individually instead of copying their directory
(this repository's `tools/check_repo.py` requires a referenced path to be a file, and the copied
result is the same). `vcpkg_make_common.cmake` is the only file with behavioural changes, all of
them inside one predicate:

```cmake
VCPKG_TARGET_IS_WINDOWS
AND CMAKE_C_COMPILER_FRONTEND_VARIANT STREQUAL "MSVC"
AND CMAKE_C_COMPILER_ID STREQUAL "Clang"
```

- `ASM_COMPILER` joins the list of programs whose directory goes on `PATH` (item 1).
- `llvm-lib` is replaced by the `llvm-ar` beside it, unwrapped, and `ARFLAGS` is reduced to `cr`
  (item 2).

A cl.exe triplet, MinGW, and every Unix triplet therefore execute the registry's code path
unchanged - the gate is not a flag a port sets, it is a property of the compiler that only
clang-cl has, and no shared line changes at all.

**The environment is the triplet's job, not the port's.** A clang-cl triplet for this graph sets
`VCPKG_LOAD_VCVARS_ENV ON` and chainloads a toolchain that selects clang-cl; that is the
community shape (walbourn's collection) and the one `docs/consumer-recipes.md` documents. The
repository's CI cells, added in the next change, follow it. Stock triplets remain what this port
promises: a consumer who never asks for clang-cl gets exactly today's behaviour, and ICU and
OpenSSL keep forcing clang-cl inside their own portfiles so a stock triplet still works.

Everything else the registry does for an MSVC frontend - the escapes, the `-LIBPATH:` entry, the
`.lib`-to-`-l` transformation of the standard libraries - is left exactly as it is. The
transformation in particular cannot be dropped: without it `kernel32.lib` and friends are
arguments ending in `.lib`, libtool classifies them as archive dependencies and passes them to
`$AR`, and llvm-ar fails on `kernel32.lib: no such file or directory` (measured). clang-cl
ignoring `-lkernel32` on a link line is harmless - every library in that list is linked by the
MSVC CRT by default, and `uuid` is already removed for Windows.

### The one change that is ICU's, not vcpkg-make's

ICU's own Windows platform file (`mh-msys-msvc`, applied through the registry port's patch) writes
lib.exe's spelling into every Makefile: `AR_OUTOPT = -OUT:` and `Makefile.inc` opens `ARFLAGS` with
`cr`. `ar-lib` translates both for lib.exe; llvm-ar answers `-OUT:icudt.lib` with its help text and
exit 0, which leaves the data library missing (measured: `icudt.lib` in `stubdata`). No
vcpkg-make change can alter a variable ICU's Makefile supplies, so `ports/icu/portfile.cmake`
passes `AR_OUTOPT=` and `ARFLAGS=cr` to the make run *in its clang-cl branch only*. Every other
port that archives through libtool is unaffected because libtool spells the archive command
`$AR $AR_FLAGS archive objects` and has no output option.

## Consequences

- **Blast radius is the whole graph, on every platform, but the semantics differ only on
  clang-cl.** Any consumer whose graph contains a make-based port receives this `vcpkg-make`
  instead of the registry's - that is what an overlay does and there is no per-port opt-out.
- **The cl.exe and Unix paths are unchanged by construction:** every edit is inside the clang-cl
  predicate, and no shared line is touched. The control is the pull request's own matrix - `node`
  depends on `libffi` and `icu`, so every Windows leg builds libffi through this port with cl.exe,
  and every Linux and macOS leg builds it through this port with gcc/clang. A green matrix is the
  evidence that the shared code did not move; a byte comparison with the registry scripts is not
  possible without a second graph, and is not what the gate promises.
- **Verified on the clang-cl path** (2026-11-04 and 2026-11-05, vcpkg 2026.10.16, VS 2022's
  LLVM 19.1.5): with a triplet of the shape above, `libffi:x64-windows-static-clang-vcvars`
  builds both configurations and `libffi:x64-windows-release-clang-vcvars` builds the shared one,
  each with the repository's own portfile and no workaround; `icu` on the static triplet builds
  with the clause above and nothing else. Evidence in issue #34.
- **A clang-cl triplet without `VCPKG_LOAD_VCVARS_ENV ON` fails, and the failure is the lesson:**
  the first try-compile reports `LNK1181: cannot open input file 'kernel32.lib'`. That is
  documented in `docs/consumer-recipes.md` and in the README's known limits rather than papered
  over with a port-side environment restore.
- The per-port workarounds this replaces are removable: `ports/icu/portfile.cmake`'s
  `ENV{INCLUDE}`/`ENV{LIB}`/`ENV{PATH}` block is redundant on a vcvars-loading clang-cl triplet
  (kept for a follow-up so this change stays one subject), while its
  `DISABLE_MSVC_TRANSFORMATIONS` still matters on a stock triplet - there the *detected* compiler
  is cl.exe even though the portfile names clang-cl, so the predicate is false and the registry's
  `-Xcompiler` escaping is in effect. `ports/libffi` never carried these workarounds in the
  tracked tree.
- `vcpkg-make` is a helper port: its own version is the registry's, and the overlay records why
  its content differs in `docs/overlay-replacements.md`. Its binary cache entry is distinct from
  the registry's, as for every overlay.
- A clang-cl without an `llvm-ar` next to `llvm-lib` is refused with a fatal error; every LLVM
  installation ships both, and the alternative is a cryptic `cr: command not found`.
- **Not done here:** the `*-clang` triplets and a CI cell. A consumer keeps stock triplets and is
  unaffected until that change lands, which is what makes this overlay safe to merge on its own.

## Revisit when

The registry port drives a clang-cl triplet itself. Then this overlay is deleted rather than
maintained, and the date in its filename records how long it existed. If vcpkg ever ships a
clang-cl triplet of its own, the documented triplet requirement disappears with it.
