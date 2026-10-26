# vcpkg-port-node

Build the **Node.js source tree** (including V8) into a **linkable library**, delivered as  
**vcpkg overlay ports** — so a C++ project can embed Node.js without vendoring Node.js  
itself.

```cmake
find_package(unofficial-node CONFIG REQUIRED)
target_link_libraries(my_app PRIVATE unofficial::node::node)
```

## Status

Released: **`20261026_26.12.1_vcpkg-2026.10.16`** (the first release was
`20261024_26.12.0_vcpkg-2026.07.29`), and this repository is in its maintenance period — every
change goes through a pull request, and the full matrix is green on `main` on every push.

|             |                                                 |
| ----------- | ----------------------------------------------- |
| Node.js     | v26.12.1 (v26 line)                             |
| vcpkg       | 2026.10.16 (pinned)                             |
| Build route | `configure.py` → `gyp -f ninja` → `ninja`       |
| Delivery    | static or shared library + CMake config, as overlay ports |

The machine-readable record of these pins — plus V8's version, `NODE_MODULE_VERSION` and  
Node.js's LTS dates — is [versions.json](versions.json), and  
[docs/versioning.md](docs/versioning.md) explains how versions, branches and tags relate.

## Why an overlay port

V8 is a Node.js-maintained fork and Node.js offers no externalize channel for it, so the  
Node.js source tree always has to be built here. That alone rules out a submission to the  
curated vcpkg registry, which is why consumption is through `overlay-ports`.

Everything Node.js *does* let us externalize (`--shared-*`, `--with-intl=system-icu`) is  
meant to come from vcpkg instead of the vendored copy, so a consumer's dependency graph  
holds one version of each library rather than two. The current verdict for every dependency  
is written up under `docs/`.

## Using it

```jsonc
// vcpkg-configuration.json in your project
{
  "overlay-ports": ["path/to/vcpkg-port-node/ports"]
}
```

```jsonc
// vcpkg.json in your project
{
  "dependencies": [
    { "name": "node", "features": ["tools"] }
  ]
}
```

The `tools` feature installs a `node` executable together with `npm` and `npx`;  
`test-suite` installs the official Node.js test suite so a consumer can run it against its  
own embedder binary.

Both the working example and the validation harness live in `test/`: `cmake --preset …`  
followed by `ctest`. `test/README.md` has the details.

Consumers need **C++20**: Node.js and V8 headers require it, and the port declares it on the  
imported target, so a CMake consumer inherits it either way.

## Known limits

The goal is that this port behaves like an ordinary vcpkg port: stock triplets, no special  
settings, no surprises when it is linked next to other ports. Where that cannot hold, it is  
listed here, with the reason, rather than left for you to discover at link time.

**Only limits caused by something outside this repository's control are listed here.** Anything  
this repository intends to support but has not finished is a work item, not a limit: it lives  
in the [issues](https://github.com/hz2769514387/vcpkg-port-node/issues) (the build matrix is  
grouped in [#11](https://github.com/hz2769514387/vcpkg-port-node/issues/11)) and in the status  
section above.

### It is an overlay port, and consuming it means building Node.js

`find_package(unofficial-node CONFIG REQUIRED)` only resolves if your  
`vcpkg-configuration.json` lists this repository under `overlay-ports`. That cannot be  
avoided: V8 is a Node.js-maintained fork with no externalize channel, so the Node.js source  
tree always has to be built from here, and the curated registry has no mechanism that could  
host it.

Two consequences worth planning for, both of them properties of the port rather than choices:

- **It builds the Node.js source tree.** The first configure of your project therefore costs  
  tens of minutes, and the machine needs what the build documents: `cargo`, a Python 3, and on  
  Windows the clang-cl component of Visual Studio 2022 or newer (the port locates clang-cl and  
  assembles the MSVC command-line environment itself, so a stock triplet is still all *you* need  
  to select). A cross build needs one more thing, and it is easy to miss: the Rust standard  
  library for the *target* architecture, because `cargo --target` builds Node.js's Rust crates  
  and rustup ships the standard library only for the architecture it was installed for. On an  
  arm64 machine building `x64-osx`, for instance: `rustup target add x86_64-apple-darwin`.
- **Nothing is shipped prebuilt.** A binary cache makes repeat builds cheap, but there is no  
  artifact to download that skips the build.

### On macOS the library's minimum system version is the graph's, not Node.js's

Node.js builds for macOS 13.5, and that number is Node.js's own: it is pinned in  
`common.gypi` and there is no knob for it. Everything else in the graph is vcpkg's: each  
dependency is built with the deployment target vcpkg was given - `VCPKG_OSX_DEPLOYMENT_TARGET`,  
stated in a triplet, because no stock vcpkg triplet pins one - or, when it was given none, the  
SDK's default, which is newer than 13.5 on any current machine. The port therefore hands the  
graph's value to Node.js's own build (`patches/0018`, through `GYP_DEFINES`) and keeps Node.js's  
floor as a lower bound, so the whole library agrees with its dependencies instead of the linker  
warning about every one of them (see the build log entry this replaces: `ld: warning: object file
(...libicuuc.a[...]) was built for newer 'macOS' version (15.0) than being linked (13.5)`).

The consequence to plan for: **the delivered library requires the graph's macOS version, which by  
default is the SDK's - not Node.js's 13.5.** A consumer who needs 13.5 states  
`set(VCPKG_OSX_DEPLOYMENT_TARGET 13.5)` in their triplet, and the dependencies and Node.js both  
follow it.

### Windows needs Visual Studio 2022 or newer

That requirement is Node.js's, not a choice made here: Node.js has required clang-cl since v24,  
and the port states gyp's Visual Studio version itself (`GYP_MSVS_VERSION=2022`,  
`ports/node/portfile.cmake`) because gyp's own probe reads registry keys that a modern  
installation does not write. Nothing older than the Visual Studio 2022 toolset has been built or  
measured in this repository, so 2022 is the floor rather than a ceiling. The presets under  
`test/` therefore name no generator: CMake uses the newest Visual Studio on the machine, and a  
machine whose newest is 2019 fails inside the port's build, with gyp's or the compiler's  
message, instead of at generator lookup.

### Overlaying this repository replaces ten registry ports for your whole dependency graph

Declaring `overlay-ports` gives every consumer in the graph this repository's build of any port  
it ships under a registry name. Sixteen do: the zlib Chromium fork, `simdutf`, `sqlite3`,  
`simdjson`, `nghttp2`, `llhttp`, `hdr-histogram`, `ada-url`, `libuv`, `brotli`, `libffi`,  
`mbedtls`, `frozen`, `tcb-span`, `lief` and `perfetto`. The full table -  
the version each one replaces, what the graph gets instead, and what it means if you also link  
that library directly - is in [docs/overlay-replacements.md](docs/overlay-replacements.md).  
Read the `mbedtls` row first: the overlay is 4.0 while the registry at the pinned baseline  
ships 3.6, which is a breaking API change, not a version bump.

The zlib fork is the one whose blast radius is largest in practice: **248 ports in the  
registry depend on `zlib`**, and overlaying this repository's ports gives every one of them  
the Chromium fork, not just node. It cannot be opted out of while still consuming this port.  
It is deliberate, it is measured and tested rather than assumed, and the evidence and the  
accepted downside are written up in `docs/zlib-fork.md` and `docs/decisions/`.

Node.js does not use madler's zlib: it vendors the Chromium fork, with SIMD crc32/adler32 and  
inflate/deflate corrections upstream never merged. This repository ships that fork as  
`ports/zlib`, because Node.js's compression behaviour and `process.versions.zlib` are the  
reference the port is held to.

### The consumer's configuration and CRT must match the installed library

These are MSVC's ABI, not this port's rules:

- **Runtime library.** A `/MD` consumer cannot link a `/MT` library, or the other way round  
  (`LNK2038 RuntimeLibrary mismatch`). Which one the library uses is decided by the triplet  
  that installed the port, through `VCPKG_CRT_LINKAGE`.
- **Configuration.** A Debug consumer needs a Debug library: MSVC's Debug configuration is the  
  debug CRT (`/MTd` or `/MDd`) plus `_ITERATOR_DEBUG_LEVEL=2`, and a Release library carries  
  the release values. A release-only triplet installs nothing under `debug/lib`, so a Debug  
  consumer cannot link such an install at all.

**Release and RelWithDebInfo work against any install.** `RelWithDebInfo` is the release ABI  
with full debug information, so it is the configuration to use when what you need is to debug  
your own code - and you are never pushed into Release to do it. **Debug needs a dual triplet**  
(a stock one, with `VCPKG_BUILD_TYPE` unset), which is what makes the port build a Debug  
library as well.

The exported config checks both at configure time and fails with the fix in the message,  
instead of letting you meet them as a wall of linker errors.

### A Windows x64 Debug consumer cannot format dates through ICU

`new Intl.DateTimeFormat(...)` aborts the process, inside ICU's own destructor:

```
debug_heap.cpp(904) : Assertion failed: _CrtIsValidHeapPointer(block)
```

reached from `icu_78::DateFormatSymbols::initializeData` via V8's `CreateICUDateFormatFromCache`.
The CRT's debug heap rejects a buffer ICU hands to `free()`.

Scope, measured (2026-10-21) on one dual-triplet install:

| Consumer | `Intl.DateTimeFormat` |
|---|---|
| Windows x64, **Debug** | aborts |
| Windows x64, Release / RelWithDebInfo | fine |
| Windows **arm64**, Debug | fine |
| the same install's own `node.exe`, Debug | fine |

So it is not ICU and not libnode - the install's own executable does the same call in the same
Debug library. It is the combination in one process of Node.js compiled with clang-cl `/MTd`
and ICU compiled with `cl` `/MTd`, which the UCRT checks unconditionally. Two candidate
mechanisms were ruled out: ICU's Debug objects do carry `/DEFAULTLIB:LIBCMTD` (202 directives in
`icuucd.lib`) and `sizeof(icu::UnicodeString)` is 64 under `cl` and clang-cl, `/MT` and `/MTd`
alike.

The node24 line hit the identical assertion and recorded it the same way (`_CrtIsValidHeapPointer`
is unconditional, clearing `_CRTDBG_ALLOC_MEM_DF` does not help, the dialog blocks the process);
see `docs/memory/2026-10-15.md` on `legacy/node24_vcpkg-2026.07.29`.

**What to do:** use `RelWithDebInfo` when the reason for Debug is debugging your own code - it is
the release ABI with full debug information, and it is what this port recommends for that anyway.
If you need a Debug CRT consumer and you call `Intl.DateTimeFormat`, there is no fix from this
side today. `test/smoke` asserts number formatting on that cell and skips only the date half.

### Node.js is compiled with clang-cl on Windows, gcc on Linux and clang on macOS

That is Node.js's own build and test matrix, and this port does not change it. What *you* use to
compile your own code is a separate choice, and the supported way to make it is in your preset:

| Platform | Recommended | How to state it |
|---|---|---|
| Windows | `clang-cl` | `toolset: {value: ClangCL, strategy: set}` |
| Linux | `gcc` | `CMAKE_C_COMPILER: gcc`, `CMAKE_CXX_COMPILER: g++` |
| macOS | `clang` | `CMAKE_C_COMPILER: clang`, `CMAKE_CXX_COMPILER: clang++` |

**On Windows do not use `CMAKE_CXX_COMPILER` to ask for clang.** A Visual Studio generator
derives its compiler from its toolset and ignores that variable entirely - by bare name and by
full path alike, with no error and no warning, so you get `cl.exe` while believing otherwise.
Measured on Visual Studio 2022 / CMake 3.31, and the whole of [ADR 0007](docs/decisions/0007-toolchain-configuration-and-linkage-policy.md).

Every other combination - `cl.exe` on Windows, clang on Linux, a mixed build whose dependencies
come from one compiler and whose executable from another - is **legal and unverified**: nothing
here blocks it, and nothing here promises it works. Changing those settings is fine; the result
is yours. Note that on Windows "mixed" is the default rather than something you opt into: the
port always builds Node.js with clang-cl, so naming no toolset already gives you a `cl.exe`
executable against a clang-cl library.

### A shared libnode has to be findable at run time

With `VCPKG_LIBRARY_LINKAGE=dynamic` the delivered library is a DLL, a `.so` or a `.dylib`, and
finding it is the consumer's job: copy it next to your executable on Windows, or give your target
a `BUILD_RPATH` on Unix. `test/CMakeLists.txt` does both, in one small function you can copy.

Two things differ from the static library, and both are deliberate: a shared `libnode` already
contains the externalized dependencies, so the exported config links the library and **nothing
else** - linking them again would put a second copy of every symbol into the process - and the
addon story is not the same, because native addons bind against symbols the hosting executable
exports.

### It integrates with CMake, and only with CMake

The port installs a CMake package config (`unofficial-node`). There is no pkg-config file and  
no other build-system integration, because the delivered artifact is a set of static archives  
produced by Node.js's own gyp build rather than a single library a generic tool could describe.  
A non-CMake consumer has to link the archives, the externalized dependencies and the system  
libraries by hand; the generated config is the readable description of that link line.

## Continuous integration

Four gates, described in `docs/ci.md`. Every dimension this repository verifies is exercised **on
every push**, and the one it does not is named rather than implied:

- a seconds-long lint pass;
- `ci.yml` — the port built through `test/` across all six platform cells (both architectures on
  Windows, Linux and macOS), consumed as Release **and** as RelWithDebInfo, with Node.js's own
  test suite run against the Release consumer of every leg;
- `debug.yml` — a **Debug** consumer, which needs a Debug library and therefore its own install.
  Five cells: Windows x64 and arm64, macOS arm64 and x64, and Linux x64 — the last as two jobs
  (install, then build and test) because a cold dual install of Node.js with gcc is 4.5 hours on
  a four-core runner. **Linux arm64 has no Debug leg**: its install does not finish inside six
  hours, and `docs/ci.md` has the numbers;
- `matrix.yml` — the rest of the matrix: the dynamic CRT on Windows and a **shared libnode** on
  every platform. These legs are non-blocking until each has completed a build.

Debug and the wider matrix are separate workflows rather than extra legs of `ci.yml` because a
job that installed the port for every configuration and ran the suite for each would exceed
GitHub's six-hour job limit, while three workflows run in parallel and each stays inside it.

Plus two daily watchers that compare the pinned Node.js and vcpkg releases against upstream and
open an issue when either moves, because nothing else will: Renovate and Dependabot have no
vcpkg manager. Every run's logs from every leg end up in a single archive, and the run summary
carries the test counts and the first error.

## Repository layout


| Path                 | Purpose                                                                                |
| -------------------- | -------------------------------------------------------------------------------------- |
| `ports/`             | The overlay ports: `node` plus any dependency that has to be pinned or patched         |
| `test/`              | Consumer-side example project and the validation harness (ctest)                       |
| `tools/`             | Maintenance scripts: the version-tree hasher, the hygiene checker, the release watcher |
| `versions/`          | vcpkg version files (one per port), carrying each port's git-tree                      |
| `.github/workflows/` | Continuous integration; see `docs/ci.md`                                               |
| `docs/`              | Design notes, dependency disposition, build and CI reference                           |
| `docs/decisions/`    | Architecture decision records                                                          |
| `tools/`             | Repository tooling: version tree, hygiene check, release watchers, benchmark comparison |

## Documentation

- `docs/` — reference material, English, versioned with the code.
- `docs/decisions/` — why things are the way they are.
- `AGENTS.md` — working rules for this repository (useful for humans too).
- `CHANGELOG.md` — one entry per release tag, the same text as that tag's release body.
- `CONTRIBUTING.md` — the short version of `AGENTS.md` for a pull request.
- `SECURITY.md` — how to report a problem privately, and what is in scope here.

## License

MIT — see `LICENSE`. Vendored and patched third-party code keeps its own license; the  
corresponding NOTICE files are preserved.
