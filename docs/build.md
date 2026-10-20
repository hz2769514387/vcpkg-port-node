# Build reference — how the port builds Node.js, and what each quirk costs

Reference for the `gyp → ninja` route on the v26 line: the externalization mechanism, the
platform behaviour that is not obvious from upstream's documentation, and the fixes the
port has to carry. Findings marked **measured** were reproduced on this machine against
`node-v26.12.0`; see §5 for the exact commands.

The disposition of individual dependencies is in
[dependency-disposition.md](dependency-disposition.md).

## 1. The route

`configure.py` → `gyp -f ninja` → `ninja`. Upstream drives the same generator through
MSBuild on Windows and Make on Unix; `--ninja` selects `ninja-win` on Windows.

Notes that matter when driving it from a port:

- `--ninja` is passed through to gyp as `-f ninja-<flavor>`; gyp splits that into
  `format=ninja` + `flavor=win` (`tools/gyp/pylib/gyp/__init__.py`).
- gyp's VS detection reads registry keys that modern Visual Studio does not write, so
  `GYP_MSVS_VERSION` **and** `GYP_MSVS_OVERRIDE_PATH` must be set (measured: every
  `_DetectVisualStudioVersions` probe misses on a stock VS 2022 install).
- `DXSDK_DIR` must be set to a non-existent path on non-English Windows: gyp's
  `_FindDirectXInstallation` decodes `reg.exe` output as UTF-8 and dies on a localized
  code page (measured).
- The bundled OpenSSL needs an assembler: `nasm` (the port acquires it from vcpkg's tool
  cache), otherwise configure stops with "Did not find a new enough assembler".
- The compiler for the `cc`/`cxx` ninja rules comes from `CC`/`CXX`, not from
  `--clang-cl=…`. `--clang-cl=<ver>` only sets the gyp `clang` variable and the
  `lib/clang/<ver>` runtime path. Windows needs clang-cl for Node.js itself (upstream
  `vcbuild.bat` requirement) and the ninja generator emits `cc = clang-cl` once `CC`/`CXX`
  say so (measured).

## 2. How a dependency becomes external

`configure_library(name, output)` in `configure.py` is the single mechanism for all the
`--shared-*` channels:

- it writes `node_shared_<name> = true` into `config.gypi`;
- `--shared-<name>-includes=<dir>` is appended to the top-level `target_defaults.include_dirs`
  (so every target compiles against the external headers);
- `--shared-<name>-libpath=<dir>` becomes `/LIBPATH:<dir>` (Windows) or `-L<dir>`;
- `--shared-<name>-libname=<a,b,c>` becomes one `-l<name>` per entry.

Two consequences that are easy to get wrong:

1. **Without `--shared-<name>-libname`, and without pkg-config, no library is added to the
   link line at all.** The `pkgname=[…]` list in `configure.py` feeds `pkg_config()`, which
   does not exist on Windows. A Windows port must pass the libname list explicitly.
2. That list is written in pkg-config terms, so it names **header-only interface targets**
   as well as real libraries. For abseil, `configure.py` lists 63 names; vcpkg's abseil
   installs **91** `.lib` files and only **21** of them are in Node.js's list (measured).
   Passing the 63 would ask the linker for libraries that do not exist. Passing all 91
   installed names works and is what this port does.

`-l<name>` is translated to `<name>.lib` by gyp's `msvs_emulation.AdjustLibraries`, so the
ninja link line ends up with real MSVC library names.

**The list is not always `absl_*.lib`, and getting that wrong is silent.** Two cases, both
measured:

| Triplet | Libraries abseil actually installs | What to pass |
|---|---|---|
| Windows, static (the cell everything above was measured on) | 91 `absl_*.lib`, one per component | every installed name |
| Windows, dynamic (`*-windows`) | **one** library, `abseil_dll.lib` - vcpkg leaves `ABSL_BUILD_MONOLITHIC_SHARED_LIBS` at MSVC's default, which is ON, so no `absl_*.lib` exists at all | `abseil_dll` |
| POSIX (any linkage) | `libabsl_*.a` - vcpkg's abseil port calls `vcpkg_check_linkage(ONLY_STATIC_LIBRARY)` off Windows, so abseil is never a shared library there | every installed name |

Globbing `absl_*.lib` on a dynamic Windows triplet therefore yields an empty list, and an
empty list is invisible: `configure.py` simply adds no `-l` entry, the port builds for another
twenty minutes, and the first host tool to link `v8_libbase` dies with

```
v8_libbase.lib(v8_libbase.mutex.obj) : error LNK2019: unresolved external symbol
    "public: void __cdecl absl::lts_20260107::Mutex::lock(void)"
bytecode_builtins_list_generator.exe : fatal error LNK1120: 3 unresolved externals
```

which names neither abseil nor the triplet. The port now names `abseil_dll` for that case and
refuses to continue with an empty list at all.

The POSIX row has a second consequence for a **shared** libnode: since abseil is static-only
there, it cannot be a run-time dependency, so the archives have to end up *inside*
`libnode.so`. When they do not, the link still succeeds - a shared library may keep symbols
undefined - and the failure moves to the consumer, as
`libnode.so.147: undefined reference to absl::...`. The port therefore checks the built library
with `nm` and refuses if any abseil symbol is still undefined (see
`docs/dependency-disposition.md`).

## 3. What the externalization actually removes (measured)

With `--shared-abseil --shared-highway` on v26.12.0:

| Check | Result |
|---|---|
| `config.gypi` | `node_shared_abseil`/`node_shared_highway` = `"true"`; vcpkg include dir in `target_defaults.include_dirs`; 92 `-l` entries (91 `absl_*` + `hwy`) |
| `v8_base_without_compiler.ninja` | references V8's bundled `third_party/abseil-cpp` **0** times; carries the vcpkg include directory |
| build graph for `libnode` | **0** compile steps for `deps/v8/third_party/abseil-cpp` or `.../highway` |
| link inputs | `absl_*.lib` on the link lines of `libnode`, `node`, `cctest`, `embedtest`, `node_mksnapshot` |
| host tools that consume abseil and link successfully | `bytecode_builtins_list_generator.exe`, `gen-regexp-special-case.exe`, `torque.exe` |

The `abseil.gyp` / `highway.gyp` ninja files still exist after the switch — gyp emits the
target files either way — but nothing depends on them, so nothing is built from them. The
dependency edges that disappear are the ones to look at, not the file list:

```gyp
# tools/v8_gypfiles/v8.gyp (and node.gyp, twice)
['node_shared_abseil=="false"',  {'dependencies': ['abseil.gyp:abseil']}],
['node_shared_highway=="false"', {'dependencies': ['highway.gyp:highway']}],
['node_shared_simdutf=="false"', {'dependencies': ['simdutf.gyp:simdutf']}],
```

`v8.gyp` gates thirteen blocks on `node_shared_abseil=="false"`, so this is a real,
upstream-supported switch, not a coincidence of one target.

Since the failure mode here is invisible downstream - the linker silently picks one of two
definitions and the process runs - the port does not rely on this measurement staying true:
after each configuration builds, `scripts/check_no_vendored_build.py` reads the generated build
graph and fails the build if any source under a vendored copy is still compiled. It is cheap
(one pass over the ninja files, well under a second) and it is the check that would have caught
`simdutf.gyp` arriving through `ada.gyp` before a consumer did. The set it reads covers every
library this port externalizes, V8's own zlib directory included; the one deliberate exception
is Chromium's `compression_utils_portable`, the wrapper V8 calls rather than the library.

## 4. Platform quirks and fixes the port carries

Everything here is measured, and every one of them is a gyp or upstream integration issue
rather than a Node.js behaviour issue.

### 4.1 `$(Platform)` in `deps/crates/crates.gyp` — new on v26

Node 26 builds the Temporal C API from Rust (`deps/crates`, `temporal_capi`) and is enabled
by default. `crates.gyp` uses the MSBuild macro `$(Platform)` in three places (two
`node_crates_libpath` variables and one action argument). The `msvs` generator passes that
through to MSBuild; the **ninja** generator writes it verbatim, and `$(` is not valid ninja
syntax, so *no* build file can be loaded:

```
ninja: error: obj\deps\crates\node_crates.ninja:21: bad $-escape (literal $ must be written as $$)
```

Fix: replace `$(Platform)` with `<(target_arch)` (the values are the same names — `x64`,
`arm64`). With that, `cargo_build.py` runs, builds `node_crates` from the vendored crates
and the build continues (measured: `temporal_capi` and `node_crates` compile in ~19 s with
`--frozen`). The port therefore also needs a working Rust toolchain for its own build.

### 4.2 `key=value` action arguments are mangled by the MSVC argument quoting

`msvs_emulation.EscapeArg` normalizes anything that looks like a path with
`os.path.normpath`. The inspector protocol action passes
`--config_value protocol.path=../../deps/v8/include/js_protocol.pdl`, which is not a path:
normpath treats `protocol.path=..` as a directory and collapses it, dropping the key and the
leading `../../`. The generator then dies with

```
AttributeError: 'X' object has no attribute 'path'
```

Fix: skip normalization when the argument contains `=`. `code_generator.py` only accepts
`--config_value` entries of the form `key=value`, so a bare path is silently ignored.

### 4.3 Localized compiler output hides real failures

gyp's Windows tool decodes the output of `link.exe`/`rc.exe`/`mt.exe` as UTF-8
(`tools/gyp/pylib/gyp/win_tool.py`, 5 sites; `msvs_emulation.py`, 3 sites). On a Chinese
Windows the localized messages are GBK, so a genuine link failure surfaces as

```
UnicodeDecodeError: 'utf-8' codec can't decode byte 0xd5 in position 2
```

with the linker's diagnostics thrown away — which is worse than a crash, because it looks
like a tooling problem. Fix: decode with `errors="replace"`, and (for diagnosis)
`set VSLANG=1033` to make MSVC emit ASCII messages. Note that `out/<config>/gyp-win-tool`
is a **copy** emitted by gyp, so patching `tools/gyp/pylib/gyp/win_tool.py` only takes
effect after regenerating the build files.

### 4.4 Precompiled header paths and `/std:` under the ninja generator

The ninja generator used to drop the MSBuild `LanguageStandard` setting (V8 then fails with
"`C++20 or later required`"), and `_GetPchFlags` emits `/Yu`, `/FI`, `/Yc` and `/Fp` with a
source-root-relative header path, while ninja runs commands from the build directory. Both
need converting; the translation unit that *creates* the PCH must also not carry `/Yu`.

Status: the port carries this fix; on the machine used for these measurements the PCH stage
is where a full build currently stops (§6).

### 4.5 `node.gyp` still links with MSBuild-shaped `/WHOLEARCHIVE` paths

Four occurrences (`node.gyp:665-666`, `1193-1194`):

```gyp
'/WHOLEARCHIVE:<(PRODUCT_DIR)/lib/<(STATIC_LIB_PREFIX)node_base<(STATIC_LIB_SUFFIX)',
'/WHOLEARCHIVE:<(PRODUCT_DIR)/lib/<(STATIC_LIB_PREFIX)v8_base_without_compiler<(STATIC_LIB_SUFFIX)',
```

The msvs generator puts static libraries in the output root; the ninja generator puts them
under `obj/` (and for the V8 one, under `obj/tools/v8_gypfiles/`). Without a fix, the link
fails with `LNK1356`. Fix as a string replacement in `node.gyp` **before** running
`configure.py`: the ninja files are generated inside configure, so editing afterwards has no
effect.

### 4.6 Bundled ICU does not build with clang-cl in this configuration

With `CC=CXX=clang-cl`, building the vendored `deps/icu-small` fails in bulk (measured: over
a thousand failing targets in `source/tools/toolutil` and the ICU libraries). The port uses
`--with-intl=system-icu`, so ICU is not built from the Node.js tree at all — the
externalization of ICU is load-bearing, not an optimisation. ([ADR 0008](
decisions/0008-icu-comes-from-vcpkg.md) records why that is a decision and not a workaround:
vendoring ICU would put a second ICU into any process that also uses one of the 25 ports in
this baseline that depend on vcpkg's `icu`.)

### 4.7 OpenSSL's C code has to be compiled by clang-cl

Node.js requires clang-cl on Windows (`vcbuild.bat` forces it for >= 24), and vcpkg builds its
ports with cl.exe, so OpenSSL arrived in every Node.js process as the one library compiled by
something else. On arm64 that difference is not harmless:

| OpenSSL C code built by | arm64 Windows official suite |
|---|---|
| `cl.exe` (what vcpkg does by default) | **250 cases `--- CRASHED ---`**, no other output |
| `clang-cl` (this port, since ADR 0009) | **100% passed** (29 and 20 tests), **0 crashes** |

The assembly was tried first and is not the cause: building with `no-asm` — which is what
Node.js does for its own vendored OpenSSL on Windows arm64 — left the crash count at 250 with
a byte-identical set of 254 failing tests. The assembler was already clang in the baseline, so
holding it constant is also what makes the result above about the C compiler alone. See
[ADR 0009](decisions/0009-openssl-is-built-with-clang-cl.md).

## 5. Reproducing these measurements

```sh
# 1. configure with the two switches (Windows; the port does the equivalent from CMake)
python configure.py --ninja --dest-cpu=x64 --clang-cl=19.1.5 \
  --shared-abseil --shared-abseil-includes=<inc> --shared-abseil-libpath=<lib> \
  --shared-abseil-libname=<comma separated list of installed absl_*.lib> \
  --shared-highway --shared-highway-includes=<inc> --shared-highway-libpath=<lib> \
  --shared-highway-libname=hwy

# 2. what the graph contains (this is the evidence, not the file list)
ninja -C out/Release -n libnode | grep -c 'third_party/abseil-cpp'   # 0
grep -c 'x64-windows-static-rel' out/Release/obj/tools/v8_gypfiles/v8_base_without_compiler.ninja
grep -l 'absl_base.lib' out/Release/libnode.ninja out/Release/node.ninja

# 3. build a subset (host tools + a few V8 translation units)
ninja -C out/Release -k 0 <target>.obj
```

Environment: `GYP_MSVS_VERSION=2022`, `GYP_MSVS_OVERRIDE_PATH=<VS root>`,
`DXSDK_DIR=C:\nonexistent`, `VSLANG=1033`, `CC=CXX=clang-cl`, `LIB` including the vcpkg
`lib` directory (gyp links by name; the `/LIBPATH:` entries configure emits do not reach
every link line).

## 6. Full build status

The port builds `libnode.lib` successfully on `x64-windows-static` with Node.js v26.12.0
(measured: 2026-10-15). Both Release and Debug configurations complete; the full
`vcpkg install` including binary cache submission takes ~40 min on this machine.

### 6.1 What was needed beyond §4

The fixes in §4 were necessary but not sufficient. Three additional problems surfaced
during the full build:

1. **simdutf `atomic_*` symbols missing.** V8 v26.12.0 bundles simdutf 7.7.0; vcpkg ships
   8.2.0. V8 calls `simdutf::atomic_binary_to_base64` and `simdutf::atomic_base64_to_binary_safe`,
   which are gated by `SIMDUTF_ATOMIC_REF` (requires `__cpp_lib_atomic_ref >= 201806L`, a
   C++20 feature). vcpkg's simdutf defaults to `SIMDUTF_CXX_STANDARD=11`, so the `atomic_*`
   functions are not compiled into the library. Fix: an overlay port `ports/simdutf` that
   forces `SIMDUTF_CXX_STANDARD=20`.

2. **simdutf gyp target not reachable after externalization.** `v8.gyp` gates the
   `simdutf.gyp:simdutf` dependency on `node_shared_simdutf=="false"`, so externalizing
   simdutf removes the dependency edge — but `simdutf.gyp` is still unconditionally
   included by `ada.gyp`, and the V8 host tools (`mksnapshot.exe`, `node_mksnapshot.exe`)
   need `-lsimdutf` on their link line. Fix: patch `v8.gyp` to add `simdutf.gyp:simdutf`
   as an **unconditional** dependency of `v8_base_without_compiler` (type `none`, no
   sources), and propagate `-lsimdutf` through `all_dependent_settings.libraries` on that
   target.

3. **`simdutf.lib` vs `-lsimdutf` in gyp `libraries`.** A bare `simdutf.lib` in
   `all_dependent_settings.libraries` is treated by the ninja generator as a build output
   path (`tools\v8_gypfiles\simdutf.lib`), not a system library. Using `-lsimdutf` lets the
   linker search `LIB` and find the vcpkg-installed copy.

### 6.2 Installed artifacts

| Artifact | Path |
|---|---|
| `libnode.lib` (Release) | `lib/libnode.lib` (9.7 MB) |
| `libnode.lib` (Debug) | `debug/lib/libnode.lib` (12 MB) |
| Headers | `include/node/` (246 `.h` files) |
| CMake config | `share/unofficial-node/unofficial-node-config.cmake` |
| CMake version | `share/unofficial-node/unofficial-node-config-version.cmake` |

The CMake config declares `unofficial::node::node` and pulls in all shared dependencies
(zlib, OpenSSL, libuv, llhttp, c-ares, brotli, ada, simdjson, simdutf, ngtcp2, zstd, ICU,
sqlite3, hdr_histogram, highway) via `find_dependency`.
### 6.3 sqlite3 overlay port

vcpkg's official `sqlite3` port does not enable `SQLITE_ENABLE_FTS3_PARENTHESIS`
or `SQLITE_ENABLE_RBU`, both of which Node.js requires (its own
`deps/sqlite3/sqlite3.gyp` enables them). The `fts3` feature only sets
`SQLITE_ENABLE_FTS3`; the `session` feature sets `SQLITE_ENABLE_SESSION` and
`SQLITE_ENABLE_PREUPDATE_HOOK` but not `SQLITE_ENABLE_RBU`.

Fix: a `ports/sqlite3` overlay port that adds `SQLITE_ENABLE_FTS3_PARENTHESIS`
to the `fts3` feature and `SQLITE_ENABLE_RBU` to the `session` feature, and
adds the corresponding `#cmakedefine` entries to `sqlite3-vcpkg-config.h.in`
so they are visible to `sqlite3.c` at compile time. All other files are
identical to the vcpkg 2026.07.29 `sqlite3` port.

### 6.4 Test suite

The official suite runs on every push through the consumer test project; how it is run, how
to read a result, and the discipline for what may be allowed to fail are in
[node-suite.md](node-suite.md). Result numbers are deliberately not recorded here — they
belong to the run that produced them, and a number in a document goes stale while still
looking authoritative.

The one fact worth keeping next to the build notes: the first full run on
`x64-windows-static` passed all but 30 of 4990 cases, and every one of those 30 was either
an environment permission (symlinks) or an upstream Windows bug, none of them the port.

## 7. What the first CI run found

The first real CI run (2026-10-16) did what a local build could not: it ran the port on
machines this project does not own. Two defects surfaced, both of them places where the port
had been relying on something it never stated.

### 7.1 Apple: the frameworks the static archives drag in

The macOS leg failed inside the port build, linking a host tool:

```
Undefined symbols for architecture arm64:
  "_CFRelease", "_CFStringGetCString", "_CFTimeZoneCopyDefault", ...
  referenced from absl::lts_20260107::time_internal::cctz::local_time_zone() in libabsl_time_zone.a
```

abseil's `time_zone` reaches CoreFoundation, and Node.js's own certificate gathering reaches
Security. Upstream states both in `node.gyp`'s `libraries` for the executable it builds, but
the port builds several host tools (js2c, mksnapshot, torque) through the same gyp files, and
nothing told them about frameworks. Fix: the portfile exports `LDFLAGS` and `LDFLAGS_host`
with `-framework CoreFoundation -framework Security` on Apple, which gyp's ninja generator
reads when it runs (inside `configure.py`). The exported consumer config already carried the
same two frameworks.

### 7.2 Windows: js2c's uninformative assertion

The Windows leg failed in the `node_js2c` action with
`Assertion failed: utf16_count != 0, file ..\..\tools\js2c.cc, line 568` — which is reached
only when a file handed to the generator is empty or not valid UTF-8. Only three files in the
whole input set take that path (`lib/internal/cli_table.js`, `lib/internal/timers.js`,
`deps/acorn/acorn/dist/acorn.js`), all three are valid UTF-8 in the source tarball, and no
patch touches them, so the message names neither the file nor the reason. Patch
`0015-js2c-report-unusable-input.patch` turns it into a build error that reports the file and
the first bad byte offset, and separately reports the case where the input is valid yet
simdutf still reports a zero length (which would mean the linked simdutf disagrees with the
headers it was compiled against).

The diagnostic confirmed the second case: the input (`deps/acorn/acorn/dist/acorn.js`,
245 232 bytes) is valid UTF-8, `simdutf::utf16_length_from_utf8` returns 245 204, and
`simdutf::validate_utf8_with_errors` reports no error — yet
`simdutf::convert_utf8_to_utf16` returns 0. The three functions disagree on the same
input. The CI runner uses MSVC 14.51 (Visual Studio 18); a local build with MSVC 14.44
(Visual Studio 2022) on the identical source and options does not reproduce the defect.
The cause is a code-generation issue in simdutf v8.2.0's `convert_utf8_to_utf16` fast
path under MSVC 14.51 `/O2`.

Patch `0017-js2c-fallback-simdutf-convert.patch` replaces the `assert(utf16_count != 0)`
with a fallback: when `convert_utf8_to_utf16` returns 0, js2c decodes the input
byte-by-byte into UTF-16. The fallback is only reached on the broken fast path, so it
costs nothing where simdutf works correctly; where it does not, the build produces the
same embedded JS it would have produced with a working simdutf. Patch 0015 is kept: it
names the file and shape in the log, which is how the root cause was identified.

### 7.3 Debug builds were drowning in Torque's source positions

A Debug build's log is an order of magnitude larger than a Release one - 16 MB against 232 KB
on the same machine - and the reason is not warnings about our code. Only the Debug
configuration emits source positions, and Torque writes them as
`ca_.SetSourcePosition("..\..\deps\v8/src/builtins/aggregate-error.tq", 21)` - an absolute
Windows path inside a C string literal, with native separators. `\.` and `\d` are not escape
sequences, so the compiler emits one warning per occurrence: 59,692 of them in a single Debug
build, out of 60,032 warning lines in total.

Two consequences, not one. The obvious one is the noise: a real warning has to be found among
sixty thousand fake ones, which is how the 39 `-Wmacro-redefined` warnings from V8's own
bigint headers stay invisible. The less obvious one is that the generated string is silently
mangled - `\v` in `deps\v8` is a vertical tab - so the source positions carried in the Debug
library point at a path that does not exist.

Upstream never sees this because its Windows build goes through MSBuild, which hands Torque
forward slashes; the ninja generator hands it native ones. Patch
`0016-torque-normalize-source-position-paths.patch` normalizes the separators in
`CSAGenerator::EmitSourcePosition`, the same defect class as patches 0009 and 0010. Verified
by rebuilding the `torque` tool, regenerating one CSA file and compiling it: the emitted path
becomes `../../deps/v8/src/builtins/aggregate-error.tq`, and that translation unit compiles
without a single warning.

## 7. Shared libnode: making the shared objects findable (measured)

A dynamic triplet turns every dependency into a shared object, and three separate consumers
of those objects then need help finding them. Each failure below was measured on a CI leg,
and each one is silent about its cause: the messages name neither the tool nor the missing
library.

### 7.1 The port's own host tools

`torque`, `mksnapshot`, `node_mksnapshot` and `bytecode_builtins_list_generator` **run**
during the build - they generate the sources everything else compiles - and they are linked
against the dependencies. gyp puts every executable in the output root (`out/<config>/`,
`ComputeOutput`: "Some products go into the output root"), where nothing findable sits, so
the first one to run dies with

```
out/Release/torque: error while loading shared libraries: libada.so.4: cannot open shared object file
dyld: Library not loaded: @rpath/libz.1.3.2.1.dylib
```

an hour into the leg. Fix, both halves in `portfile.cmake`: a **relative** rpath on every
link (`$ORIGIN` / `@loader_path`, plus `.../../lib` for the node executable's post-install
layout), and one symlink per dependency in the output root, so `$ORIGIN` has something to
point at. `LDFLAGS_host` is deliberately not used for this: gyp's ninja generator only
honours a separate host toolset when cross-compiling (`gyp.common.CrossCompileRequested`),
and the port passes `--no-cross-compiling` everywhere, so every link - host tools included -
reads `LDFLAGS`.

An absolute rpath is never an option, not even for the transient host tools: the GitHub
runner path shape (`/home/runner/work/<repo>/<repo>/vcpkg/installed/<triplet>/lib`) is the
same on every machine, so it would not be inert on a consumer's machine - it would find
whatever some other build left at that path.

The rpath spelling has to survive two layers: the ninja generator writes `LDFLAGS` verbatim
into `build.ninja`, and the command is run through `sh`. `$` is ninja's escape character and
`sh` would expand `$ORIGIN` to nothing, so the value must be spelled `\$$ORIGIN` (ninja:
`$$` -> `$`; sh: `\$` -> `$`). `node.gyp` spells its own the same way
(`'-Wl,-rpath,\$$ORIGIN/../lib'`). `@loader_path` has no `$` and needs no such care.

### 7.2 The installed artifacts

The exported config links libnode itself and nothing else (a consumer that linked the
dependencies again would get two copies of every symbol), so libnode.so finds its
dependencies through its own rpath: they are installed next to it in `<prefix>/lib`, and
`$ORIGIN` / `@loader_path` names that directory without naming this machine. The installed
`node` executable lives in `<prefix>/tools/node` and needs `$ORIGIN/../lib`.

### 7.3 The consumer side (what the test project does, and why)

Windows has no rpath. The loader searches the executable's own directory and then PATH -
**not** the directory of the DLL whose import is being resolved. Measured, because the
intuition says otherwise: an executable in one directory loading a DLL from another, with
that DLL's dependency sitting right beside it, fails with `ERROR_MOD_NOT_FOUND` (126) until
the dependency is either next to the executable or on PATH. So the test project copies the
whole `bin/` directory next to every consumer executable (`node_test_runtime_libs`), and the
same set next to `tools/node/node.exe`, which is not a CMake target and cannot be handed its
DLLs at build time.

Two traps in that mechanism, both measured:

* A **bare** generator expression in a `POST_BUILD` command is written into a Visual Studio
  project as `$<0:...>` / `$<1:...>` and reaches the command line as literal text ("The
  system cannot find the path specified"). Quoting the expression is what makes it evaluate
  per configuration; `COMMAND_EXPAND_LISTS` then turns the semicolons into separate
  arguments. (The repository's Windows presets use Ninja, where the bare form also works -
  the quoted form works on both.)
* ctest splits the `ENVIRONMENT` property on semicolons, so a `PATH` value with more than
  one directory is truncated at the first one and the inherited PATH is lost with it. That
  is why the tools executable gets the DLLs copied next to it instead of a `PATH` entry.

### 7.4 `MultiThreadedDebugDLL` is the value; `MultiThreadedDLLDebug` is not

CMake's four `CMAKE_MSVC_RUNTIME_LIBRARY` values are `MultiThreaded`, `MultiThreadedDLL`,
`MultiThreadedDebug` and `MultiThreadedDebugDLL` - Debug before DLL. The test presets for
the dynamic-CRT triplets spelled it `MultiThreadedDLL$<$<CONFIG:Debug>:Debug>`, which is
valid for Release and RelWithDebInfo and evaluates to the nonexistent
`MultiThreadedDLLDebug` for Debug, where CMake rejects it ("MSVC_RUNTIME_LIBRARY value
'MultiThreadedDLLDebug' not known for this CXX compiler") during the compiler-ABI
try-compile - a message that names neither the preset nor the value's origin. The correct
spelling, the one vcpkg's own `windows.cmake` uses, is
`MultiThreaded$<$<CONFIG:Debug>:Debug>DLL`. Verified with clang-cl locally before the fix.
