# Build reference — how the port builds Node.js, and what each quirk costs

Reference for the `gyp → ninja` route on the v26 line: the externalization mechanism, the
platform behaviour that is not obvious from upstream's documentation, and the fixes the
port has to carry. Findings marked **measured** were reproduced on this machine against
`node-v26.11.1`; see §5 for the exact commands.

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

## 3. What the externalization actually removes (measured)

With `--shared-abseil --shared-highway` on v26.11.1:

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
externalization of ICU is load-bearing, not an optimisation.

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

The port builds `libnode.lib` successfully on `x64-windows-static` with Node.js v26.11.1
(measured: 2026-10-15). Both Release and Debug configurations complete; the full
`vcpkg install` including binary cache submission takes ~40 min on this machine.

### 6.1 What was needed beyond §4

The fixes in §4 were necessary but not sufficient. Three additional problems surfaced
during the full build:

1. **simdutf `atomic_*` symbols missing.** V8 v26.11.1 bundles simdutf 7.7.0; vcpkg ships
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

### 6.4 Test-suite results

The official test-suite passes with 4960 / 4990 tests (99.4 %) on
`x64-windows-static` Release (measured: 2026-10-16). All 30 failures are
environment-specific or upstream test bugs on Windows; none are caused by the
port. See [test-suite-results.md](test-suite-results.md) for the full
breakdown.

| Category | Count | Cause |
|---|---|---|
| Windows symlink EPERM | 28 | No `SeCreateSymbolicLinkPrivilege` |
| CRLF in tsc output | 1 | `test-snapshot-typescript` — upstream Windows bug |
| FORCE_COLOR / NO_COLOR | 1 | `test-runner-reporters` — env interaction |
