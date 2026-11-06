# vcpkg-port-node

**English** | [简体中文](README.zh-CN.md)

Build the **Node.js source tree** (including V8) into a **linkable library**, delivered as  
**vcpkg overlay ports** — so a C++ project can embed Node.js without vendoring Node.js  
itself.

```cmake
find_package(unofficial-node CONFIG REQUIRED)
target_link_libraries(my_app PRIVATE unofficial::node::node)
```

## Is this what you are looking for?

- Embedding **Node.js in a C++ application** - you want a library to link, not a `node.exe` to shell out to.
- **Either linkage**: a static libnode linked into your executable - which is also how you get the static
  CRT on Windows - or a shared `.dll` / `.so` / `.dylib` that one host process loads and others share.
- A **vcpkg port for `node` / libnode** - overlay ports, with every dependency resolved from one vcpkg version tree.
- A **C++ host driving Node.js over N-API**, with Node.js's own dependencies built by vcpkg instead of vendored inside it.

If none of those is you: this is not a Node.js distribution, not a bare JavaScript engine (V8 ships as
part of Node.js here, not on its own), and not something the curated vcpkg registry could host - *Why an
overlay port* below says why. Where the support stops is in *Known limits*.

## Status

Released: **`20261024_26.12.0_vcpkg-2026.07.29`**. `main` is ahead of that tag — it carries
Node.js v26.13.0 on vcpkg 2026.10.16, and the next release is prepared from it. Every change
goes through a pull request, and the full matrix is green on `main` on every push.

|             |                                                 |
| ----------- | ----------------------------------------------- |
| Node.js     | v26.13.0 (v26 line, LTS)                        |
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

Everything below is a property of the port or of the platforms it builds on. Unfinished support
is not a limit: it lives in the [issues](https://github.com/hz2769514387/vcpkg-port-node/issues).

| Limit | Why | What to do |
|---|---|---|
| Consuming it builds Node.js from source - the first configure costs tens of minutes, and nothing is shipped prebuilt | V8 is a Node.js-maintained fork with no prebuilt channel, and the curated registry cannot host an overlay | Plan for the build: `cargo`, a Python 3, and (Windows) the clang-cl component of Visual Studio 2022. A cross build also needs the Rust std for the target architecture (`rustup target add ...`) |
| Overlaying replaces **21 registry ports** for the whole graph | `overlay-ports` shadows them everywhere; the zlib fork alone has 248 dependent ports | Read [docs/overlay-replacements.md](docs/overlay-replacements.md) first - the `mbedtls` row is a breaking API change (4.0 vs 3.6) |
| On macOS the deployment target is the graph's, not Node.js's 13.5 | Node.js pins 13.5 with no knob; every dependency follows the triplet | Set `VCPKG_OSX_DEPLOYMENT_TARGET 13.5` in the triplet if you need that floor |
| Windows needs Visual Studio 2022 or newer | Node.js 24 and later require clang-cl | Nothing older has been built or measured |
| A clang-cl triplet has to load vcvars and include vcpkg's Windows platform file | vcpkg loads vcvars for its own MSVC triplets only, so a custom clang-cl triplet starts without the MSVC/UCRT headers and libraries; and without vcpkg's `windows.cmake` every CMake dependency keeps clang-cl's default `/MD` | Set `VCPKG_LOAD_VCVARS_ENV ON` and chainload [test/cmake/toolchains/clang-cl.cmake](test/cmake/toolchains/clang-cl.cmake) - [consumer-recipes.md](docs/consumer-recipes.md) §6 has the shape, ADR 0012 the measurement |
| A Debug consumer needs a dual triplet | MSVC ABI: a Debug consumer links a Debug library, and a release-only triplet installs none | Use `RelWithDebInfo` when the reason for Debug is debugging your own code - it is the release ABI |
| On Windows, name the compiler with the toolset, not `CMAKE_CXX_COMPILER` | A Visual Studio generator derives its compiler from the toolset and ignores that variable silently | `toolset: {value: ClangCL, strategy: set}` in the preset; on Linux and macOS the compilers go through `CMAKE_{C,CXX}_COMPILER` |
| A shared libnode must be findable at run time, and links nothing else | The DLL/`.so`/`.dylib` already contains the externalized dependencies | Copy it next to the executable or set `BUILD_RPATH`; do not link the dependencies a second time |
| CMake is the only supported build system | The artifact is a set of gyp-built static archives, not a single describable library | Non-CMake consumers reproduce the link line the exported config describes, by hand |

## Continuous integration

Four gates, described in `docs/ci.md`. Every dimension this repository verifies is exercised **on
every push**, and the one it does not is named rather than implied:

- a seconds-long lint pass;
- `ci.yml` — the port built through `test/` across all six platform cells (both architectures on
  Windows, Linux and macOS), consumed as Release **and** as RelWithDebInfo, with Node.js's own
  test suite run against the Release consumer of every leg;
- `debug.yml` — a **Debug** consumer, which needs a Debug library and therefore its own install.
  Four cells: Windows x64 and arm64, macOS arm64 and x64. **Neither Linux cell has a Debug leg**:
  a dual install of Node.js on four cores is 5h36m of vcpkg work with every dependency cached, so
  the x64 leg landed on either side of GitHub's six-hour job limit from one run to the next, and
  arm64 never finished at all. `docs/ci.md` has the three measurements;
- `matrix.yml` — the rest of the matrix: the dynamic CRT on Windows, a **shared libnode** on
  every platform, and the **clang-cl dependency graph** on Windows. Twelve cells; eight block a
  merge, and the four that do not are tracked in
  [#35](https://github.com/hz2769514387/vcpkg-port-node/issues/35).

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
