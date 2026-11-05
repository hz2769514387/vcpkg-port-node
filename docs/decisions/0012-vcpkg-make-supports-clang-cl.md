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
`CMAKE_C_COMPILER_FRONTEND_VARIANT STREQUAL "MSVC"`, a condition clang-cl also satisfies. Three
of them are real, measured on libffi (the only libtool-based port in the graph) and on ICU:

1. The assembler is not in the list of programs whose spaced directory is moved onto `PATH`, so
   `CCAS` keeps `C:/Program Files/.../clang-cl.exe` and the msys shell splits it (libffi compiles
   `src/x86/win64.S`).
2. `CMAKE_AR` is `llvm-lib.exe`, wrapped as `AR='ar-lib llvm-lib.exe'` with `ARFLAGS=cr`; ar-lib
   passes its trailing arguments through as a command, so the shell answers
   `./libtool: line 150: cr: command not found`. The registry's own comment already says the
   tool for this job is llvm-ar, unwrapped - it just does not recognise `llvm-lib`.
3. A chainloaded clang-cl triplet never gets vcvars (vcpkg loads it for its own MSVC triplets
   only), so `INCLUDE`, `LIB` and the MSVC/SDK `bin` directories are missing in the process that
   starts the shell - the first try-compile dies with `LNK1181: cannot open input file
   'kernel32.lib'`.

Two others that ADR 0011 listed turn out **not** to be gaps, and their absence matters for the
decision below:

- **`-Xcompiler` / `-Xlinker`.** They are a libtool guard, not a compiler spelling: libtool strips
  them before the compiler sees them, and clang-cl ignores them where they do leak through -
  configure runs without libtool and warns "unknown argument ignored" while keeping the option
  that follows (measured; `-Xcompiler -DHELLO` still defines `HELLO`). Removing them is what
  *breaks* a clang-cl build: a Debug configuration's `-RTC1` then reaches libtool's own option
  parser as `-R TC1` and the link dies with "only absolute run-paths are allowed" (measured on
  libffi's Debug link). They stay.
- **`-LIBPATH:`** prepended to `LDFLAGS`. With the escaping in place it is passed through to
  link.exe, which accepts the dash spelling; it only breaks when escaping is off, which is what
  the ICU workaround does with `DISABLE_MSVC_TRANSFORMATIONS`. It stays as well.

Each of the three real gaps can be worked around in a portfile, and two ports did (icu carries
`ENV{INCLUDE}`, `ENV{LIB}`, `ENV{PATH}` and `DISABLE_MSVC_TRANSFORMATIONS`, and libffi's failed
attempt carried four workarounds). None of them is about ICU or libffi, and every make-based port
a consumer adds would need the same code.

## Decision

**`ports/vcpkg-make` is an overlay of the registry's `vcpkg-make`, version `2026-07-09` with
`port-version` 2, carrying the fixes that make the flow drive a clang-cl triplet.** The registry
port's manifest, wrapper scripts and `configure.ac` are copied unchanged; the portfile differs
only in naming its two wrapper files individually instead of copying their directory (this
repository's `tools/check_repo.py` requires a referenced path to be a file, and the copied result
is the same), and every behavioural difference is in `vcpkg_make_common.cmake` and
`vcpkg_make.cmake`, inside one predicate:

```cmake
VCPKG_TARGET_IS_WINDOWS
AND CMAKE_C_COMPILER_FRONTEND_VARIANT STREQUAL "MSVC"
AND CMAKE_C_COMPILER_ID STREQUAL "Clang"
```

A cl.exe triplet, MinGW, and every Unix triplet therefore execute the registry's code path
unchanged - the gate is not a flag a port sets, it is a property of the compiler that only
clang-cl has. The three changes:

- `ASM_COMPILER` joins the list of programs whose directory goes on `PATH` (gap 1).
- `llvm-lib` is replaced by the `llvm-ar` beside it, unwrapped, and `ARFLAGS` is reduced to `cr`
  (gap 2). The static-linker flags the registry would append (`/machine:x64`) make llvm-ar print
  its help and exit 0 without writing an archive - measured with LLVM 19.1.5.
- `z_vcpkg_make_prepare_env` puts the `INCLUDE`, `LIB` and `PATH` the get-vars probe recorded
  back into the environment (gap 3). `PATH` is appended, not substituted, so msys and the tool
  directories stay in front.

Everything else the registry does for an MSVC frontend - the `-Xcompiler` / `-Xlinker` escaping,
the `-LIBPATH:` entry in `LDFLAGS`, the `.lib`-to-`-l` transformation of the standard libraries -
is left exactly as it is, because each of them was measured to be necessary on a clang-cl
triplet as well once the three gaps above are closed. The `.lib`-to-`-l` transformation in
particular cannot be dropped: without it `kernel32.lib` and friends are arguments ending in
`.lib`, libtool classifies them as archive dependencies and passes them to `$AR`, and llvm-ar
fails on `kernel32.lib: no such file or directory` (measured). clang-cl ignoring `-lkernel32` on
a link line is harmless - every library in that list is linked by the MSVC CRT by default, and
`uuid` is already removed for Windows.

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
- **The cl.exe and Unix paths are unchanged by construction:** every difference is inside the
  clang-cl predicate, and the one shared edit is an extra cached `include()` of the get-vars
  file. The control is the pull request's own matrix - `node` depends on `libffi` and `icu`, so
  every Windows leg builds libffi through this port with cl.exe, and every Linux and macOS leg
  builds it through this port with gcc/clang. A green matrix is the evidence that the shared
  code did not move; a byte comparison with the registry scripts is not possible without a
  second graph, and is not what the gate promises.
- **Verified on the clang-cl path:** `libffi:x64-windows-static-clang` (both configurations) and
  `libffi:x64-windows-release-clang` build and install with the repository's own portfile and no
  workaround, and `icu` on the static triplet builds with the clause above and nothing else added.
  Evidence in issue #34.
- The per-port workarounds this replaces are removable: `ports/icu/portfile.cmake`'s
  `ENV{INCLUDE}`/`ENV{LIB}`/`ENV{PATH}` block is redundant on a clang-cl triplet now (kept for a
  follow-up so this change stays one subject), while its `DISABLE_MSVC_TRANSFORMATIONS` still
  matters on a stock triplet - there the *detected* compiler is cl.exe even though the portfile
  names clang-cl, so the predicate is false and the registry's `-Xcompiler` escaping is in
  effect. `ports/libffi` never carried these workarounds in the tracked tree.
- `vcpkg-make` is a helper port: its own version is the registry's, and the overlay records why
  its content differs in `docs/overlay-replacements.md`. Its binary cache entry is distinct from
  the registry's, as for every overlay.
- A clang-cl without an `llvm-ar` next to `llvm-lib` is refused with a fatal error; every LLVM
  installation ships both, and the alternative is a cryptic `cr: command not found`.
- **Not done here:** the `*-clang` triplets and a CI cell. A consumer keeps stock triplets and is
  unaffected until that change lands, which is what makes this overlay safe to merge on its own.

## Revisit when

The registry port drives a clang-cl triplet itself. Then this overlay is deleted rather than
maintained, and the date in its filename records how long it existed.
