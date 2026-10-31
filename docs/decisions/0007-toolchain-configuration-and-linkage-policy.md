# 7. Toolchain, configuration and linkage policy for consumers

- Status: Accepted
- Date: 2026-10-18
- Supersedes: [0004](0004-continuous-integration.md) — its two-tier gate stays, but the
  matrix it gates is redefined here.

## Context

The port was verified on one cell of its configuration matrix, and a consumer who picked any
other standard vcpkg combination was the first to find out whether it worked
([issue #11](https://github.com/hz2769514387/vcpkg-port-node/issues/11)). Five dimensions are
involved: platform, build configuration, library linkage, CRT linkage and compiler.

Three questions had to be settled by measurement, because the plausible answer is wrong in
each case.

### 1. How does a consumer state a compiler in `CMakePresets.json`?

Measured 2026-10-18 on Windows (Visual Studio 2022 Community 17.14, CMake 3.31.7), with a
two-file project:

| What the preset says | Compiler CMake actually used |
|---|---|
| `CMAKE_CXX_COMPILER: clang-cl` (bare name), Visual Studio generator | `cl.exe` — **silently ignored** |
| `CMAKE_CXX_COMPILER: <full path to clang-cl.exe>`, Visual Studio generator | `cl.exe` — **silently ignored** |
| `toolset: {value: ClangCL, strategy: set}`, Visual Studio generator | `clang-cl` 19.1.5 ✔ |
| no `toolset` at all | `cl.exe` 19.44 ✔ |

A Visual Studio generator does not read `CMAKE_C_COMPILER` / `CMAKE_CXX_COMPILER` at all: it
derives the compiler from its toolset. There is no error and no warning — the consumer gets
`cl.exe` while believing they asked for clang. That makes `CMAKE_CXX_COMPILER` an actively
harmful recommendation on Windows, because the failure mode is silence rather than a
diagnostic. On Ninja and Makefiles it works normally, so it remains the right field on Linux
and macOS.

### 2. Can the port be Release while the consumer is Debug?

Measured 2026-10-18 against a locally installed tree, by building the repository's own
embedder (`test/cases/embed/main.cpp`) through the real consumer project:

| Install (`VCPKG_BUILD_TYPE`) | Consumer configuration | Result |
|---|---|---|
| unset (dual, stock triplet) | Debug | ✔ links in ~10 s; `node_embed --version` → `v26.12.0`, and `-e` reports `configuration: Debug` |
| unset (dual) | RelWithDebInfo | ✔ links and runs; the library still reports `Release` |
| `release` (community `*-release` triplet) | RelWithDebInfo | ✔ links and runs against the release-only install |
| `release` | Debug | ✘ `LNK1181: cannot open … debug/lib/libnode.lib` |

The Windows half of that is MSVC's ABI, not a choice: a Debug consumer compiles with `/MDd`
or `/MTd` and `_ITERATOR_DEBUG_LEVEL=2`, and a Release static library carries
`RuntimeLibrary=MT_StaticRelease` and level 0, so the link ends in a wall of `LNK2038`. It
cannot be fixed from the port's side. On Linux and macOS there is no such mismatch — Debug is
`-g -O0` and no ABI-affecting assertion macro is on by default — so the same split would
link, which is exactly why the rule has to be stated per platform rather than globally.

`RelWithDebInfo` is the configuration that answers the actual need. It is the *release* ABI
(`/MD` or `/MT`, level 0, `NDEBUG`) plus full debug information, so a consumer gets
breakpoints and stepping through **their own** code against the released library, without
paying for a second build of Node.js. Measured: it works against a release-only install,
which is the install the push gate produces.

### 3. Is a dynamic library a hard limit?

`ports/node/portfile.cmake` called `vcpkg_check_linkage(ONLY_STATIC_LIBRARY)`, so
`VCPKG_LIBRARY_LINKAGE=dynamic` was rejected before any evidence existed for rejecting it.
Read from the Node.js v26.12.0 tree:

- `node_shared` makes `node_lib_type` a `shared_library` (`node.gyp`), and `--shared` is a
  first-class `configure.py` option;
- on Windows the DLL is linked once, then `gen_node_def` derives a module-definition file
  **from that DLL's own export table** and the DLL is linked again against it, so the export
  set is whatever the DLL already exported rather than a curated list
  (`node.gyp`, `tools/gen_node_def.cc`);
- `common.gypi` defines `BUILDING_V8_SHARED=1` on Windows, so V8's embedding symbols carry
  `__declspec(dllexport)` and therefore land in that export table;
- on Linux and macOS the obvious way to hide them is commented out in `node.gyp`
  (`-fvisibility=hidden`), so a shared build exports everything by default.

So a shared `libnode` is not blocked from outside, and a static-only promise was a decision
made without evidence. Node.js upstream does not ship a `libnode` for every platform though,
so the port does not inherit a tested configuration here.

## Decision

### Compilers — one per platform, named in the preset

The port compiles Node.js with **clang-cl on Windows**, **gcc on Linux** and **clang on
macOS**, which is what Node.js upstream builds and tests with. That is the port's own build
and is not affected by anything a consumer selects.

A consumer selects **their own** compiler, and the supported way to do it is:

| Platform | Recommended, and what CI verifies | How it is stated in `CMakePresets.json` |
|---|---|---|
| Windows | `clang-cl` | `toolset: {value: ClangCL, strategy: set}` — **not** `CMAKE_CXX_COMPILER`, which a Visual Studio generator ignores in silence |
| Linux | `gcc` | `CMAKE_C_COMPILER: gcc`, `CMAKE_CXX_COMPILER: g++` |
| macOS | `clang` | `CMAKE_C_COMPILER: clang`, `CMAKE_CXX_COMPILER: clang++` |

Every other combination — `cl.exe` on Windows, clang on Linux, a mixed build where the
dependencies come from one compiler and the consumer's executable from another — is **not
blocked** and is **not verified**: it is an advanced user's own experiment and this
repository makes no promise about it. The port does not detect it and does not fail on it;
the statement lives in the README's *Known limits* and in `test/README.md`.

The mixed Windows case deserves one sentence, because it is what happens by default and not
something anyone opts into: the port always builds Node.js with clang-cl, so a consumer who
names no toolset is already building a `cl.exe` executable against a clang-cl library. That
is a legal MSVC-ABI mix, and it is what the Windows CI legs did before this ADR.

### Configurations — three, with the install deciding which are available

- `Release` and `RelWithDebInfo` are supported against **any** install, release-only or dual.
- `Debug` is supported against a **dual** install (a stock triplet, `VCPKG_BUILD_TYPE`
  unset). Against a release-only install it cannot work on Windows, and the exported config
  says so at configure time rather than letting the link fail.

A consumer is never forced into Release: `RelWithDebInfo` is always available and is the
configuration to reach for when the need is "debug my own code".

### Library linkage and CRT — both, as ordinary vcpkg triplets

`static` and `dynamic` are both supported, and on Windows both `/MT` and `/MD`. Every cell is
reachable through a triplet that ships with vcpkg, so this repository still carries no
triplet file of its own:

| Cell | Triplet |
|---|---|
| Windows, static library, `/MT` | `x64-windows-static` / `arm64-windows-static` |
| Windows, static library, `/MD` | `x64-windows-static-md` / `arm64-windows-static-md` |
| Windows, dynamic library, `/MD` | `x64-windows` / `arm64-windows` |
| Linux, static / dynamic | `x64-linux` / `x64-linux-dynamic` (and the arm64 pair) |
| macOS, static / dynamic | `arm64-osx` / `arm64-osx-dynamic` (and the x64 pair) |

Where a dynamic build behaves differently from a static one, the difference goes into the
README's *Known limits* rather than into the port's prose.

### Everything above is proven in `test/`, on push

A cell that CI does not build is a cell this repository does not claim. `test/` carries a
preset per cell and CI builds and runs all of them, Node.js's own suite included; the
README's status and limits text is a restatement of what the matrix actually builds.

## Consequences

- `test/CMakePresets.json` grows variants, and its recommended preset per platform keeps the
  name of the triplet it selects (the rest carry a documented suffix). The suffix rule is
  written down in `test/README.md`, because "the preset name is the triplet" was a decision
  from 2026-10-17 and the variants have to stay readable next to it.
- The exported config's Debug guard has to work on multi-config generators, where
  `CMAKE_BUILD_TYPE` is empty and the existing `STREQUAL "Debug"` test never fired.
- Supporting dynamic linkage means the port's install and its exported config branch on
  `VCPKG_LIBRARY_LINKAGE`: a shared `libnode` already contains the externalized dependencies,
  so a consumer must not link them a second time, and the DLL has to be findable at run time.
- The push gate gets more expensive. It is controlled by the binary cache rather than by
  moving cells off the push path: a push that changes no port reuses every archive, and only
  the tests are paid for again.
