# Consumer-side test project

This directory is the answer to "does the node port actually work for someone else". It is a
plain CMake project that consumes the port the way any consumer would - overlay ports, a
manifest, a stock vcpkg triplet, `find_package(unofficial-node CONFIG)` - and then proves the
result is still Node.js.

It is never installed anywhere and it is not an example to copy into another build: the
`embedder/` directory is the example, everything else is verification.

## What is in here

| Path | What it verifies |
|---|---|
| `embedder/` | `unofficial::node::node` links into a consumer executable that behaves like `node.exe`. Doubles as the example everyone asks for, and as the shell the official suite runs against. |
| `embedding/` | What embedding has to support beyond that: exit-code semantics, `worker_threads`, spawning a child process, linking the port next to the very libraries it externalizes, a library that hides the port behind a PRIVATE link, and driving the runtime on a thread the host owns. |
| `smoke/` | Seconds. Node.js identity, and whether each externalized dependency really came from vcpkg. Runs on every push. |
| `official_suite/` | Node.js's own suite, through its own driver, labelled `node-suite`, plus its skip lists. Minutes to an hour. |

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

Every preset names a triplet that ships with vcpkg, so this repository still carries no triplet
file. Both architectures on each of the three platforms, both library linkages, and on Windows
both CRTs:

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
legitimately have downloaded. CI checks out release 2026.07.29 instead (ADR 0005). Running
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
| `-DNODE_TEST_SKIP=test-foo` | One-off skips for a single run. Long-lived ones belong in `official_suite/node-suite-skips.txt`, which requires a reason |

Fast runs skip the heavy label:

```sh
ctest --test-dir build/x64-windows-static -C Release -LE node-suite --output-on-failure
```

## Skip lists

`official_suite/node-suite-skips.txt` and `official_suite/node-suite-skips-symlink.txt` are the single source
of truth, with one required reason per entry - a skip nobody can explain is a bug waiting to
be forgotten. The second file is applied only when probing shows this machine cannot create
symlinks, because that is a permission, not a platform property: it fails in a plain local
Windows shell and works with Developer Mode and in most CI images.

Neither file lists anything upstream already marks SKIP or FLAKY in its own `*.status` files:
the driver reads those, and duplicating them would freeze a decision that is upstream's to
change.
