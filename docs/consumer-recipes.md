# Consumer recipes

Five shapes a consumer actually builds, each with the triplet, the preset and the two or three
lines of CMake that make it work. Four of them resolve to a triplet that ships with vcpkg; the
clang-cl one needs a triplet you supply, because vcpkg has none for clang-cl. This repository's
own `test/cmake/triplets/` are CI cells, not recipes, and copying one is how a downstream consumer
met a CRT mismatch at configure time (issue #61).

Everything here except §6 is exercised by `test/` on every push, on both architectures of all
three platforms; §6 is exercised by the four clang-cl cells in `matrix.yml` (ADR 0013). §7 is
exercised by `test/cases/addon` on the same legs, including the static and shared Windows cells.

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

## 4. Cross build: `x64-osx` from an arm64 Mac

```sh
rustup target add x86_64-apple-darwin     # cargo --target needs the target's standard library
```

then a preset with `"CMAKE_OSX_ARCHITECTURES": "x86_64"` and `VCPKG_TARGET_TRIPLET: x64-osx`. The
port builds its own host tools for the target as well - it passes `--no-cross-compiling` - so the
build and its tests execute x86_64 binaries on the arm64 machine, which needs Rosetta 2. There is
no Windows or Linux cross leg: neither has a supported story in this repository's matrix.

## 5. What you do not need

- **A triplet file.** Every recipe above except the clang-cl one in §6 is a stock triplet. This
  repository carries ten of its own and they are CI cells with `set(VCPKG_BUILD_TYPE release)`:
  six release-only variants of the shared and `/MD` cells, and the four clang-cl cells (ADR 0013).
- **`-DCMAKE_POLICY_DEFAULT_CMP0091=NEW`, or any CRT workaround for a dependency.** A dependency's
  own `cmake_minimum_required` cannot flip the CRT out from under you: vcpkg puts `/MT` or `/MD`
  into `CMAKE_C_FLAGS_RELEASE` and `CMAKE_C_FLAGS_DEBUG` itself (`scripts/toolchains/windows.cmake`),
  which is independent of policy `CMP0091`. Measured on c-ares 1.34.9, whose `CMakeLists.txt` asks
  for 3.5.0...3.10.0: its generated build file carries `/MT` on a static triplet.
- **A list of libraries to link.** The exported config describes the link line; that is what it is
  for, and on a static build it is the only readable description of it.

## 6. Windows, compiled by clang-cl

Node.js builds itself with clang-cl on Windows, and a consumer whose own code uses the `ClangCL`
toolset should build the dependency graph with the same compiler. vcpkg ships no clang-cl
triplet, so this is the one shape that needs a triplet file you supply. The community collection
is maintained by a vcpkg contributor (`walbourn/vcpkg`, branch `clangcltriplets`,
`triplets/community/x64-clangcl-*.cmake`); its shape is the requirement, not the file:

```cmake
set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE static)          # or dynamic, matching your application
set(VCPKG_LIBRARY_LINKAGE static)      # or dynamic
set(VCPKG_CHAINLOAD_TOOLCHAIN_FILE "<a toolchain that selects clang-cl>")
set(VCPKG_LOAD_VCVARS_ENV ON)
```

That toolchain has to do two things, and the second one is easy to miss:

1. select the compiler - `set(CMAKE_C_COMPILER/CMAKE_CXX_COMPILER .../clang-cl.exe)` plus the
   target flag (`-m64`, `--target=arm64-pc-windows-msvc`, ...);
2. include vcpkg's own platform file, `${VCPKG_ROOT}/scripts/toolchains/windows.cmake`, which
   writes `/MT` or `/MD` into `CMAKE_C_FLAGS_*` and sets `CMAKE_SYSTEM_NAME` and the processor.
   Without it every CMake-based dependency falls back to clang-cl's default (`/MD`), and a static
   triplet then cannot link: `simdutf.lib` and `libuv.lib` came back `MD_DynamicRelease` against
   node's `/MT` host tools (`LNK2038`, `LNK2019`) - measured. Inside the chainloaded file,
   `CMAKE_PARENT_LIST_FILE` is the vcpkg checkout's `scripts/buildsystems/vcpkg.cmake`, which is
   how the path is found in a try-compile too (`CMAKE_TOOLCHAIN_FILE` is empty there).

`VCPKG_LOAD_VCVARS_ENV ON` is the other line that matters. vcpkg loads vcvars for its own MSVC
triplets and skips it for anything else, so without it the make-based ports in the graph start
with no `INCLUDE` and no `LIB` and the first try-compile dies on `kernel32.lib` (measured; the
README's known limits records it). With it, the environment, the linker and the SDK's `rc.exe`
come from vcvars exactly as they do for a stock triplet.

The chainloaded toolchain is in this repository too, at
[`test/cmake/toolchains/clang-cl.cmake`](../test/cmake/toolchains/clang-cl.cmake), and it is the
part to copy: it selects the compiler, adds the target-machine flag, and includes vcpkg's own
`scripts/toolchains/windows.cmake`. It is written for a native build on a machine of the triplet's
architecture, which is what the four CI cells are. An explicit `NODE_PORT_LLVM_BIN` (used by the
port to choose its own compiler) is not needed here; vcvars puts the Visual Studio LLVM tree on
`PATH` and `LLVMInstallDir` covers a standalone one.

Then install with `--overlay-triplets=<the directory holding your triplet>` and this repository's
`overlay-ports`, and set `toolset: {value: ClangCL, strategy: set}` in your preset so your own
code is compiled by clang-cl too. ADR 0012 records what the graph needs on top of that - an
overlay of `vcpkg-make` - and it is already in `ports/`; ADR 0013 makes the four all-clang-cl
cells part of the CI matrix.

The stock triplets stay supported. ICU and OpenSSL force clang-cl inside their own portfiles, so
a consumer who never asks for a clang-cl triplet still gets a libnode whose Windows libraries
match the compiler Node.js uses.

## 7. Loading native addons

A product that embeds Node.js usually ends up loading at least one `.node` module - a serial
port driver, an image codec, a database client built with node-addon-api. Those modules call
`napi_*` functions that they do not define themselves. On Unix the dynamic loader finds them
in the process; on Windows the module has to be linked against whoever exports them.

**A static install:** the `napi_*` implementation is in the archives your executable linked,
so your executable has to export those symbols. CMake does that with one property:

```cmake
add_executable(my_app main.cpp)
target_link_libraries(my_app PRIVATE unofficial::node::node)
set_target_properties(my_app PROPERTIES ENABLE_EXPORTS ON)

add_library(my_addon MODULE addon.cpp)
set_target_properties(my_addon PROPERTIES PREFIX "" SUFFIX ".node")
target_include_directories(my_addon PRIVATE
  "$<TARGET_PROPERTY:unofficial::node::node,INTERFACE_INCLUDE_DIRECTORIES>")
target_compile_definitions(my_addon PRIVATE BUILDING_NODE_EXTENSION)
target_link_libraries(my_addon PRIVATE my_app)
```

Without `ENABLE_EXPORTS` the application itself works perfectly and the addon fails to load
with "The specified procedure could not be found". `BUILDING_NODE_EXTENSION` is what makes
`node_api.h` declare `napi_*` as `dllimport` instead of `dllexport`. `test/cases/addon` builds
exactly this shape and loads it; `test/cases/embed` is the executable it links against.

**A shared install:** `napi_*` is exported by `libnode.dll`, so link the addon against the
imported target the config exports instead of against your executable:

```cmake
target_link_libraries(my_addon PRIVATE unofficial::node::libnode)
```

Use the config's own `NODE_PORT_SHARED` variable to choose between the two. Do **not** use
`if(TARGET unofficial::node::libnode)`: once `find_package(unofficial-node)` has loaded a
config that mentions that name, CMake reports it as an existing target on a static install too
(measured on CMake 3.31), and the link then names a target that is not really there.

On macOS a `MODULE` target resolves its undefined symbols from the process; the addon case
passes `-Wl,-undefined,dynamic_lookup` explicitly rather than relying on the generator's
default. On Linux an ordinary `MODULE` already allows undefined symbols, and `-rdynamic` on
the executable (which `ENABLE_EXPORTS` adds) puts them in the dynamic symbol table.

The headers are the ones in `<prefix>/include/node`: `node_api.h`, `js_native_api.h`,
`node_version.h` and `node_buffer.h`. `NODE_MODULE_VERSION` from those headers has to match
`process.versions.modules`; `test/cases/addon` asserts it, because a mismatch is otherwise only
reported when a prebuilt addon is rejected.

## 8. Driving the loop, and calling into JavaScript

The embedding documentation gives the lifecycle - initialize once, create an environment, load,
spin, stop - but not the arrangement a host with its own main loop needs. Four arrangements are
in use, and `test/` exercises three of them on every push:

| The host... | What it gives up | Test |
|---|---|---|
| calls `node::SpinEventLoop(env)` on its main thread | that thread: the call blocks until the loop is empty or `node::Stop` runs | `cases/embed` |
| runs the whole lifecycle on a thread it created | nothing, but every exchange with JavaScript has to be queued | `cases/thread-loop` |
| pumps `uv_run(loop, UV_RUN_NOWAIT)` itself | it must also call `platform->DrainTasks(isolate)` | `cases/host-loop` |
| registers `uv_backend_fd(loop)` in its own reactor (Linux) | portability - Windows has no equivalent descriptor under IOCP | not tested here |

The third is what a UI toolkit or a game loop needs, and it has two details that are easy to
miss: `UV_RUN_NOWAIT` never blocks, so JavaScript cannot delay the host's own iterations; and
`DrainTasks` is a separate call because V8's platform queues - microtasks, worker callbacks -
are not something `uv_run` drains. `cases/host-loop` asserts that the script's timer fires
inside one of the host's iterations rather than before or after them.

A host that keeps its own loop also calls into JavaScript from it: "run this handler", "reload
this module". That call does not pass through Node.js's execution path the way a script does,
and nodejs/node#48760 reported that a `fetch` or `net` connection started from such a
`v8::Function::Call` after `LoadEnvironment` never reached the loop. On the pinned 26.13.x tree
it does: `cases/host-call` starts one connection from the script's own listen callback and one
from a host call made afterwards, pumps the same loop, and requires both to complete. That is
the contract to rely on, and the case turns a regression into a red test instead of a product
that hangs.

Two boundaries worth knowing before the first deployment:

- **`CommonEnvironmentSetup` takes no `IsolateSettings` and no `EnvironmentFlags`.** Both are
  reachable only through the lower-level `NewIsolate` / `CreateIsolateData` /
  `CreateEnvironment` path, which `cases/low-level` exercises. Three things cost time to
  discover: the environment has to be given `InitializeOncePerProcess`'s parsed
  `args()`/`exec_args()`, not an argv you built yourself; `LoadEnvironment(env, source)` returns
  the **module body's return value**, so a script without `return` evaluates to `undefined` -
  which is a valid `MaybeLocal`, not an error; and `kNoBrowserGlobals` does not do what its
  comment suggests. Measured, it makes `fetch`, `setTimeout` and `queueMicrotask` unavailable
  while `console` and `setImmediate` stay. `cases/low-level` asserts that table for both the
  flag and `kDefaultFlags`, so a host that relies on `setTimeout` - or means to hide `console` -
  finds out there rather than in production. Upstream's own low-level example
  (`test/embedding/embedtest.cc`) pairs the path with an `EmbedderSnapshotData`; the case here
  uses `node::NewContext` instead.
- **Two `ProcessInitializationFlags` are worth setting outside a command-line program.**
  `kDisableNodeOptionsEnv` makes the process ignore `NODE_OPTIONS`, so an ambient development
  setting cannot change an embedded runtime; `kNoDefaultSignalHandling` stops Node.js from
  installing its own SIGINT/SIGTERM handlers, which a GUI application or a service that owns its
  shutdown path cannot have.

Cross-thread work has one official channel: `napi_threadsafe_function` (N-API v4 or newer),
which queues a call and runs the JavaScript callback on the loop's thread. `uv_async_send` is
the lower-level version and only wakes the loop - `cases/loop-wakeup` uses it and carries the
payload itself. `node::Stop(env)` is the exception to "never touch the runtime from another
thread": it may be called from any thread and behaves like `worker.terminate()`.

## 9. Where this stops

The README's *Known limits* is the authoritative list. Three of its rows are worth reading before a
first build: the macOS deployment target comes from the dependency graph rather than from Node.js,
Visual Studio 2022 or newer is required, and consuming this repository substitutes its build for
twenty registry ports across the whole graph. Consuming it is also building it: the first
configure costs tens of minutes.
