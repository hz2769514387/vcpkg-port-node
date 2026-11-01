# Consumer recipes

Four shapes a consumer actually builds, each with the triplet, the preset and the two or three
lines of CMake that make it work. Every one of them resolves to a triplet that ships with vcpkg:
this repository's own `test/cmake/triplets/` are CI cells, not recipes, and copying one is how a
downstream consumer met a CRT mismatch at configure time (issue #61).

Everything here is exercised by `test/` on every push, on both architectures of all three
platforms.

## 0. The three rules a preset cannot state

1. **The triplet decides the install. The consumer's configuration has to match it.** Release and
   RelWithDebInfo work against any install; Debug needs one that also holds debug libraries.
2. **On Windows the CRT is part of the ABI.** `VCPKG_CRT_LINKAGE` chose it when the port was
   built; `CMAKE_MSVC_RUNTIME_LIBRARY` names it in your project. The exported config compares the
   two at configure time and refuses a mismatch, naming the value it expects.
3. **A preset is named after the triplet it selects.** That is the whole naming convention here,
   and `tools/check_repo.py` enforces it for this repository. A deviation appends one suffix,
   `-msvc` (a `cl.exe` consumer) or `-debug`.

## 1. One executable, static CRT, static library

The shape an embedding product usually wants: a single `.exe` with no runtime dependencies. Nothing
to write but the preset - `x64-windows-static` is a stock triplet that already means "static
library, static CRT".

```json
{
  "name": "x64-windows-static",
  "binaryDir": "${sourceDir}/build/x64-windows-static",
  "cacheVariables": {
    "CMAKE_TOOLCHAIN_FILE": "$env{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake",
    "VCPKG_TARGET_TRIPLET": "x64-windows-static",
    "CMAKE_MSVC_RUNTIME_LIBRARY": "MultiThreaded$<$<CONFIG:Debug>:Debug>"
  }
}
```

```cmake
cmake_minimum_required(VERSION 3.24)
project(my_app LANGUAGES CXX)

find_package(unofficial-node CONFIG REQUIRED)
add_executable(my_app main.cpp)
target_link_libraries(my_app PRIVATE unofficial::node::node)
```

Three things come from the port rather than from this file: **C++20** (declared on the imported
target), the **stack reserve** and the **manifest** the host executable needs on Windows (both are
INTERFACE link options on `unofficial::node::node`). Nothing else has to be set.

On Linux the same shape is `x64-linux` or `arm64-linux`, with no CRT variable and the system
`gcc`/`g++`. On macOS it is `arm64-osx` or `x64-osx` with Apple's `clang`.

## 2. A shared libnode

`x64-windows`, `x64-linux-dynamic`, `arm64-osx-dynamic` and their architecture pairs. Two
differences from the static library, and both are deliberate:

```cmake
find_package(unofficial-node CONFIG REQUIRED)
target_link_libraries(my_app PRIVATE unofficial::node::node)   # and nothing else
```

- **Do not link the externalized dependencies.** A shared `libnode` already contains them; linking
  them again puts a second copy of every symbol in the process, which is the failure this
  repository exists to prevent.
- **Make the library findable at run time.** On Windows copy `libnode.dll` next to the executable.
  On Unix give the target a `BUILD_RPATH` of `$ORIGIN` / `@loader_path`; `test/CMakeLists.txt`
  does both in one small function you can copy.

A consumer that calls a dependency *directly* - an embedder driving the loop with `uv_run`, say -
adds that library to its own link line. A shared library's dependencies are loadable, not linkable
through it, on macOS and Windows alike.

## 3. A Debug consumer

A Debug consumer needs a **dual** install: a stock triplet with `VCPKG_BUILD_TYPE` unset, which is
what makes the port build Release and Debug. A release-only install (vcpkg's community `*-release`
triplets, which CI uses to fit a job limit) has nothing under `debug/lib`, and on Windows a Debug
consumer cannot link a Release library at all - the exported config says so at configure time.

**If the reason for Debug is debugging your own code, use `RelWithDebInfo` instead.** It is the
release ABI - `/MT` or `/MD`, `NDEBUG`, `_ITERATOR_DEBUG_LEVEL=0` - with full debug information,
it works against any install, and it does not pay for a second build of Node.js.

One known limit applies only to a Debug consumer: on Windows x64, `Intl.DateTimeFormat` aborts
inside ICU's destructor (#27, README *Known limits*). Windows arm64 and Release are fine.

## 4. Cross build: `x64-osx` from an arm64 Mac

```sh
rustup target add x86_64-apple-darwin     # cargo --target needs the target's standard library
```

then a preset with `"CMAKE_OSX_ARCHITECTURES": "x86_64"` and `VCPKG_TARGET_TRIPLET: x64-osx`. The
port builds its own host tools for the target as well - it passes `--no-cross-compiling` - so the
build and its tests execute x86_64 binaries on the arm64 machine, which needs Rosetta 2. There is
no Windows or Linux cross leg: neither has a supported story in this repository's matrix.

## 5. What you do not need

- **A triplet file.** Every recipe above is a stock triplet. This repository carries six of its own
  and they are CI cells with `set(VCPKG_BUILD_TYPE release)`, several of them on the dynamic CRT.
- **`-DCMAKE_POLICY_DEFAULT_CMP0091=NEW`, or any CRT workaround for a dependency.** A dependency's
  own `cmake_minimum_required` cannot flip the CRT out from under you: vcpkg puts `/MT` or `/MD`
  into `CMAKE_C_FLAGS_RELEASE` and `CMAKE_C_FLAGS_DEBUG` itself (`scripts/toolchains/windows.cmake`),
  which is independent of policy `CMP0091`. Measured on c-ares 1.34.9, whose `CMakeLists.txt` asks
  for 3.5.0...3.10.0: its generated build file carries `/MT` on a static triplet.
- **A list of libraries to link.** The exported config describes the link line; that is what it is
  for, and on a static build it is the only readable description of it.

## 6. Where this stops

The README's *Known limits* is the authoritative list, and it is short: the macOS deployment target
comes from the dependency graph rather than from Node.js, Visual Studio 2022 or newer is required,
the Windows x64 Debug ICU date crash above, and the fact that consuming this repository substitutes
its build for nineteen registry ports across the whole graph. Consuming it is also building it: the
first configure costs tens of minutes.
