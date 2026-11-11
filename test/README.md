# Consumer-side test project

This directory is the answer to "does the node port actually work for someone else". It is a
plain CMake project that consumes the port the way any consumer would - overlay ports, a
manifest, a stock vcpkg triplet, `find_package(unofficial-node CONFIG)` - and then proves the
result is still Node.js.

It is never installed anywhere and it is not an example to copy into another build: the
`cases/embed/` directory is the example, everything else is verification.

## What is in here

The cases are written from the consumer's side, not as a checklist of features that start
successfully. Where a real product loads a module graph, passes CLI flags, shuts the runtime
down, serves an HTTP request, loads a native addon or drives the loop from its own thread,
there is a case that does the same thing and asserts the result. A passing "it started" is
not treated as evidence for any of those.

| Path | What it verifies |
|---|---|
| `cases/embed/` | `unofficial::node::node` links into a consumer executable that behaves like `node.exe`, plus exit-code semantics, `worker_threads` and spawning a child process. Doubles as the example everyone asks for and as the shell the official suite runs against. |
| `cases/abi/` | The two ABI numbers a consumer reads without linking anything. |
| `cases/addon/` | A consumer-built N-API addon loads into the embedding executable: the installed headers' `NODE_MODULE_VERSION`, JS callbacks, Buffers, thrown errors, async work on libuv's pool and a thread-safe function fed by a `std::thread`. |
| `cases/application/` | A shipping application tree: `package.json` with `type: module`, ESM, CommonJS through `createRequire`, a bare `node_modules` specifier, JSON import attributes, dynamic import, top-level await, and the `process` shape a host reads. |
| `cases/cli/` | Command-line flags, `-e` in both module modes, `-p`, `--require` preloads and `NODE_OPTIONS` (compared between two runs, so no machine-specific heap constant is needed). |
| `cases/coexist/` | One process linking the port next to the very libraries it externalizes. |
| `cases/config/` | The exported config's contract: C++20, both public include trees, `/STACK` on Windows, the ABI numbers, the installed library list, a matching linkage flag, and no build-machine paths in the installed config. |
| `cases/compression/` | gzip, deflate, brotli and zstd, in both sync and stream form, with a truncated-stream error path. |
| `cases/crt/` | The executable has the CRT the preset asked for, read out of its import table; the archives agree with it. |
| `cases/crypto/` | OpenSSL-backed hashing, HMAC, AEAD, key generation, sign/verify and WebCrypto. |
| `cases/exit/` | Exit hooks, `process.exit`, `beforeExit` adding work to the loop, an `uncaughtException` handler, and the `--unhandled-rejections` switch. |
| `cases/externalization/` | Did each externalized dependency really come from vcpkg - on both hosts. |
| `cases/fs/` | Unicode and special-character filenames, promise and stream APIs, recursive copy, symlinks (probed as a capability), and a non-ASCII argument passed from CMake through ctest into the embedder's `wmain`. |
| `cases/host-loop/` | The host owns the loop and pumps it itself - the UI-toolkit arrangement. |
| `cases/install/` | The package holds what its config tells a consumer to link - and a shared install holds no archives. |
| `cases/intl/` | Full ICU locale data, calendars, collation and segmentation, plus Temporal from the Rust crate. |
| `cases/layered/` | A library that hides the port behind a PRIVATE link, and two applications on top of it. |
| `cases/lifecycle/` | Three environments started and torn down in sequence in one process, each with its own cleanup and AtExit hooks. |
| `cases/loop-wakeup/` | A native thread outside the runtime signals a `uv_async_t` on Node.js's loop, and the callback runs in a host-driven pump. |
| `cases/multi-isolate/` | Two environments alive at once, two isolates and loops, alternately pumped by the host, with separate globals. |
| `cases/net/` | Loopback HTTP/1.1, `fetch`, HTTP/2, TCP, `dns.lookup` and WHATWG URL - llhttp, nghttp2, libuv, c-ares and ada. |
| `cases/runtime/` | V8 heap statistics and explicit GC, `vm` contexts and timeouts, WebAssembly compilation, Buffers, `TextDecoder`, `structuredClone` and microtask ordering. |
| `cases/snapshot/` | The startup snapshot is there and is used - on both hosts. |
| `cases/sqlite/` | `node:sqlite` with FTS5, JSON1, math functions, a user-defined function, R*Tree, transactions and iterators. |
| `cases/suite/` | Node.js's own suite, through its own driver, labelled `node-suite`, plus its skip lists. Minutes to an hour. |
| `cases/symbols/` | No strong symbol is defined by two archives, which "it links" cannot tell you. |
| `cases/thread-loop/` | The runtime on a thread the host owns. |
| `cases/tools/` | The tools feature: `node.exe`, npm and npx. |
| `cases/workers/` | A worker pool with shared memory and message ports, and `child_process` fork/spawn with an IPC channel over `process.execPath`. |
| `cases/zlib/` | zlib resolves to one copy, through the object graph and at run time. |

`cases/` is one directory per claim: a directory holds the sources, the scripts and the `CMakeLists.txt`
of one thing this project asserts, and a case that needs an executable from another directory is handed
its path (`NODE_TEST_EMBED_DIR`) rather than reaching for `../`. The `smoke` **label** still selects the
fast tier across all of them - splitting directories did not split the group. Every new case sets
`NODE_OPTIONS` explicitly: a developer machine can carry its own language shim in that variable, and
a test that inherits it would be measuring the machine instead of the port.

`cases/embed` sets `ENABLE_EXPORTS ON` because a statically linked embedding executable has to
export the `napi_*` symbols for a consumer-built addon to load. `cases/addon` is what checks that
this property is real rather than documented; [docs/consumer-recipes.md §7](../docs/consumer-recipes.md)
has the recipe a product copies.

## Running it

```sh
export VCPKG_ROOT=/path/to/bootstrapped/vcpkg     # Windows: $env:VCPKG_ROOT = ...

cmake --preset x64-windows-static -DCMAKE_BUILD_TYPE=Release  # or: x64-linux, arm64-osx, ...
cmake --build --preset x64-windows-static --config Release
ctest --test-dir build/x64-windows-static -C Release --output-on-failure
```

A preset is named after the vcpkg triplet it selects, so the name you type is the triplet you
install. **No suffix means this repository's recommendation for its platform**; a suffix names one
deliberate deviation, and there are two: `-msvc` (a cl.exe *consumer*, see below) and `-debug`.

Tests have presets of their own, so nobody has to remember a label expression:

```sh
ctest --preset x64-windows-static-fast     # everything that takes seconds
ctest --preset x64-windows-static-all      # everything, including Node.js's own suite
```

### Which compiler you get, and how to change it

The port builds Node.js with **clang-cl on Windows**, **gcc on Linux** and **clang on macOS**,
because that is what Node.js upstream builds and tests with. That is the port's own build and
nothing here changes it.

What a preset controls is the compiler for **your** code:

| Platform | This repository recommends | How the preset states it |
|---|---|---|
| Windows | `clang-cl` | `toolset: {value: ClangCL, strategy: set}` |
| Linux | `gcc` | `CMAKE_C_COMPILER: gcc`, `CMAKE_CXX_COMPILER: g++` |
| macOS | `clang` | `CMAKE_C_COMPILER: clang`, `CMAKE_CXX_COMPILER: clang++` |

**On Windows, do not reach for `CMAKE_CXX_COMPILER`.** A Visual Studio generator derives its
compiler from the toolset and ignores `CMAKE_C_COMPILER` / `CMAKE_CXX_COMPILER` completely -
with no error and no warning. Measured on Visual Studio 2022 / CMake 3.31: asking for
`clang-cl` that way, by name or by full path, silently builds with `cl.exe`. `toolset` is the
field that works (see ADR 0007). It only works because the Windows presets name no generator,
so CMake picks the newest Visual Studio; with Ninja on Windows you are on your own.

#### Which `lld-link` does the linking, and why it matters

With the `ClangCL` toolset the linker comes from the same LLVM tree as the compiler, and **which one
depends on the toolset's host architecture**:

| Host | Linker | PE type |
|---|---|---|
| `x86` | `VC` + `Tools/Llvm/bin/lld-link.exe` | PE32 - a 32-bit process, 2 GB of address space |
| `x64` | `VC` + `Tools/Llvm/x64/bin/lld-link.exe` | PE32+ |

The static library is not small: `v8_base_without_compiler.lib` alone is **1.9 GB** in this
repository's build. A 32-bit linker reports every symbol that lives in that archive as undefined, and
the diagnostic reads like a missing library rather than a link that ran out of address space.

CMake's default host is already `Native64Bit`, and these presets now say so explicitly with
`CMAKE_VS_PLATFORM_TOOLSET_HOST_ARCHITECTURE=x64` rather than relying on it. If you pin the host to
`x86`, or override `LLVMInstallDir` to the 32-bit LLVM, the static configuration stops linking and
the error mentions neither choice. Measured from the build's diagnostic log (`-v:diag`):
`_DefaultLLVMInstallDir` ends in `Llvm/x64`, `VCToolArchitecture` is `Native64Bit`, and the link line
names the `x64` copy of `lld-link.exe`.

The `-msvc` presets are the **mixed** case: your executable compiled with `cl.exe` against a
Node.js library compiled with clang-cl. That is a legal MSVC-ABI mix, and it is what this
repository's CI did before ADR 0007 - but it is not the recommendation, it is not covered by
any promise, and changing it is on you. Note that "mixed" is not something you opt into on
Windows: naming no toolset already gives you `cl.exe` while the port stays on clang-cl.

Anything else - clang on Linux, MinGW, a different clang - is likewise not blocked and not
verified. Nothing here detects or rejects it.

### Which configuration you can use

| Configuration | Needs | Notes |
|---|---|---|
| `Release` | any install | |
| `RelWithDebInfo` | any install, **release-only included** | the release ABI plus full debug information: this is what to use when the need is to debug your own code |
| `Debug` | a **dual** install (stock triplet, `VCPKG_BUILD_TYPE` unset) | on Windows a Debug consumer is `/MTd`/`/MDd` and cannot link a Release library (`LNK2038`) |

The presets inherit one of two configuration bases, `release` or `debug`, and say so in a `-debug`
variant where that is a configure-time decision: `x64-linux-debug` and `arm64-osx-debug` (Ninja
fixes the configuration at configure time), plus `x64-windows-static-debug` and
`arm64-windows-static-debug` as *build* presets (a Visual Studio generator chooses at build time).
With an unset `VCPKG_BUILD_TYPE` a stock triplet makes the port build Release **and** Debug, so a
Debug consumer is possible; CI also names vcpkg's community **release-only** triplets
(`*-release`), whose install has no debug library, and the port's exported config says so at
configure time on Windows rather than letting the link fail with a wall of `LNK2038`.

### Debugging it

The dual triplets install both configurations, so nothing has to be prepared beyond picking the
Debug one:

- **Visual Studio** - open this folder, let it read `CMakePresets.json`, and choose
  `x64-windows-static-debug` in the configuration dropdown. The startup item is `node_embedder`.
- **Visual Studio Code** - the CMake Tools extension picks the presets up; a launch entry is all
  that is missing:

  ```json
  {
    "name": "node_embedder",
    "type": "cppvsdbg",
    "request": "launch",
    "program": "${command:cmake.launchTargetPath}",
    "cwd": "${workspaceFolder}/test"
  }
  ```

- **Command line**, on Linux or macOS where the configuration is fixed at configure time:

  ```sh
  cmake --preset x64-linux-debug && cmake --build --preset x64-linux-debug
  ```

### The rest of the matrix

Every preset is named after the triplet it selects, and that is a rule rather than a habit:
`tools/check_repo.py` fails when a preset's name and its `VCPKG_TARGET_TRIPLET` disagree. A preset
that needs to deviate appends one documented suffix - `-msvc` for a `cl.exe` consumer, `-debug`
for the Debug configuration on a single-config generator - and nothing else. Both architectures
on each of the three platforms, both library linkages, and on Windows both CRTs:

| | static library | shared library |
|---|---|---|
| Windows x64, `/MT` | `x64-windows-static` | — |
| Windows x64, `/MD` | `x64-windows-static-md` | `x64-windows` |
| Windows arm64, `/MT` | `arm64-windows-static` | — |
| Windows arm64, `/MD` | `arm64-windows-static-md` | `arm64-windows` |
| Linux x64 / arm64 | `x64-linux`, `arm64-linux` | `x64-linux-dynamic`, `arm64-linux-dynamic` |
| macOS x64 / arm64 | `x64-osx`, `arm64-osx` | `x64-osx-dynamic`, `arm64-osx-dynamic` |

Node.js recommends `/MD`; `/MT` is equally supported and equally verified, and the unsuffixed
`*-windows-static` presets keep it because that is what this repository's Windows legs have
always built.

Each of the four Windows static cells also has a clang-cl variant whose preset and triplet share
one name (`x64-windows-static-clang-release`, `arm64-windows-static-clang-release`,
`x64-windows-static-md-clang-release`, `arm64-windows-static-md-clang-release`). There the
dependency graph is built by clang-cl as well; they are CI cells rather than recommendations
(ADR 0013).

### `test/cmake/triplets/` holds CI cells, not consumer recipes

Ten of the triplets above are release-only variants that vcpkg does not ship, so this directory
carries them. Each is a stock triplet plus `set(VCPKG_BUILD_TYPE release)`, added because a dual
triplet builds Node.js twice and the slow legs do not fit in GitHub's six-hour job:

| file | registry has the same name? |
|---|---|
| `arm64-windows-release` | no |
| `arm64-windows-static-md-release` | no |
| `x64-linux-dynamic-release` | no |
| `arm64-linux-dynamic-release` | no |
| `x64-osx-dynamic-release` | no |
| `arm64-osx-dynamic-release` | no |
| `x64-windows-static-clang-release` | no |
| `arm64-windows-static-clang-release` | no |
| `x64-windows-static-md-clang-release` | no |
| `arm64-windows-static-md-clang-release` | no |

The four `*-clang-*` files are the other dimension (ADR 0013): the same static and `/MD` cells, with
every dependency built by clang-cl as well. They chainload
`test/cmake/toolchains/clang-cl.cmake`, which is the part a consumer copies and is not a CI cell.

The six stock-shaped files above are hand copies, so `tools/check_triplets.py` compares them with
the stock definitions in the pinned vcpkg checkout and reports any field that differs other than
`VCPKG_BUILD_TYPE`. It needs a checkout and therefore runs at a vcpkg bump (docs/versioning.md
§4), not in lint.

**Do not copy a triplet into a project.** They exist to fit a job limit, the shared and `/MD` ones
use the dynamic CRT, and a `/MT` consumer's install rejects that combination at configure time. A
consumer needs no triplet file for the ordinary cases - the static/`/MT` single-executable build,
the shared library, Debug, and the `x64-osx` cross build all resolve to stock triplets.
`docs/consumer-recipes.md` is where those are written up (issue #61).

On Windows the presets name no generator, so CMake uses the newest Visual Studio installed: what
the port needs is Visual Studio 2022 or newer, and that is written down under *Known limits* in
the [README](../README.md). The target machine type then follows the machine, which is why the
arm64 preset is for an arm64 machine rather than a cross build.

`x64-osx` and `x64-osx-dynamic` are cross builds: they set `CMAKE_OSX_ARCHITECTURES=x86_64` so
that an arm64 machine produces an x86_64 consumer (and vcpkg reads that back to pick `x64-osx`).
The binaries it runs then need Rosetta 2, which is a property of the machine, not of this
project.

With a shared library the runtime has to find the DLL or `.so`; the test project handles that for
its own targets, and what a consumer has to do is written in the [README](../README.md).

**Which vcpkg you point at is the pin.** The project states no `builtin-baseline` (and no
`overrides`), because on the built-in registry either one has to be a commit and resolving it
requires a git checkout of vcpkg - which would rule out the release tarball a user may
legitimately have downloaded. CI checks out release 2026.10.16 instead (ADR 0005). Running
locally against a different release is therefore allowed and is not a configuration error, but
it changes every dependency version, so results are only comparable against the pinned release.

**Do not reuse a `build/<preset>` directory after changing `VCPKG_ROOT`.** vcpkg records its own
root in the CMake cache as `Z_VCPKG_ROOT_DIR` and never recomputes it once a value is there, so
a cache left over from a different vcpkg keeps invoking that one - including from Visual
Studio's CMake integration, which reads the same cache. Delete `build/<preset>` when you move
vcpkg, and `test/.vs` if Visual Studio still points at the old one.

The configure step also builds `node` itself through vcpkg, which takes tens of minutes on a
cold cache and requires the tools the port documents: clang-cl and the MSVC command line on
Windows, cargo everywhere (Node.js 26 builds its Temporal crate from Rust).

Useful switches:

| Option | Effect |
|---|---|
| `-DNODE_TEST_SUITE=OFF` | Do not register Node.js's own suite (reduces configure-time surprises while iterating) |
| `-DNODE_TEST_SUITES=parallel` | Run fewer suites than the default set |
| `-DNODE_TEST_SHARDS=4` | Split every suite into four ctest cases, each with its own temporary directory |
| `-DNODE_TEST_JOBS=2` | Parallelism handed to the driver. Lower it if cases die with `0xC0000409` on Windows: that is commit charge exhaustion, not a crash in our code |
| `-DNODE_TEST_SKIP=test-foo` | One-off skips for a single run. Long-lived ones belong in `cases/suite/node-suite-skips.txt`, which requires a reason |

Fast runs skip the heavy label:

```sh
ctest --test-dir build/x64-windows-static -C Release -LE node-suite --output-on-failure
```

## Skip lists

`cases/suite/node-suite-skips.txt` and `cases/suite/node-suite-skips-symlink.txt` are the single source
of truth, with one required reason per entry - a skip nobody can explain is a bug waiting to
be forgotten. The second file is applied only when probing shows this machine cannot create
symlinks, because that is a permission, not a platform property: it fails in a plain local
Windows shell and works with Developer Mode and in most CI images.

Neither file lists anything upstream already marks SKIP or FLAKY in its own `*.status` files:
the driver reads those, and duplicating them would freeze a decision that is upstream's to
change.
