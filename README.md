# vcpkg-port-node

Build the **Node.js source tree** (including V8) into a **linkable library**, delivered as
**vcpkg overlay ports** — so a C++ project can embed Node.js without vendoring Node.js
itself.

```cmake
find_package(unofficial-node CONFIG REQUIRED)
target_link_libraries(my_app PRIVATE unofficial::node::node)
```

## Status

Early development: there is no release yet, no tag, and no stable interface.

| | |
|---|---|
| Node.js | v26.11.1 (v26 line) |
| vcpkg | 2026.07.29 (pinned) |
| Build route | `configure.py` → `gyp -f ninja` → `ninja` |
| Delivery | static library + CMake config, as overlay ports |

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

### Windows needs Visual Studio 2022 or newer

That requirement is Node.js's, not a choice made here: Node.js has required clang-cl since v24,
and the port states gyp's Visual Studio version itself (`GYP_MSVS_VERSION=2022`,
`ports/node/portfile.cmake`) because gyp's own probe reads registry keys that a modern
installation does not write. Nothing older than the Visual Studio 2022 toolset has been built or
measured in this repository, so 2022 is the floor rather than a ceiling. The presets under
`test/` therefore name no generator: CMake uses the newest Visual Studio on the machine, and a
machine whose newest is 2019 fails inside the port's build, with gyp's or the compiler's
message, instead of at generator lookup.

### Overlaying this port replaces zlib for your whole dependency graph

Node.js does not use madler's zlib: it vendors the Chromium fork, with SIMD crc32/adler32 and
inflate/deflate corrections upstream never merged. This repository ships that fork as
`ports/zlib`, because Node.js's compression behaviour and `process.versions.zlib` are the
reference the port is held to.

That is the one decision whose blast radius leaves this port: **248 ports in the registry
depend on `zlib`**, and overlaying this repository's ports gives every one of them the
Chromium fork, not just node. It cannot be opted out of while still consuming this port. It is
deliberate, it is measured and tested rather than assumed, and the evidence and the accepted
downside are written up in `docs/zlib-fork.md` and `docs/decisions/`.

### The consumer's configuration and CRT must match the installed library

These are MSVC's ABI, not this port's rules:

- **Runtime library.** A `/MD` consumer cannot link a `/MT` library, or the other way round
  (`LNK2038 RuntimeLibrary mismatch`). Which one the library uses is decided by the triplet
  that installed the port, through `VCPKG_CRT_LINKAGE`.
- **Configuration.** A Debug consumer needs a Debug library. A release-only triplet installs
  nothing under `debug/lib`, so a Debug consumer cannot link such an install at all.

The exported config checks both at configure time and fails with the fix in the message,
instead of letting you meet them as a wall of linker errors.

### It integrates with CMake, and only with CMake

The port installs a CMake package config (`unofficial-node`). There is no pkg-config file and
no other build-system integration, because the delivered artifact is a set of static archives
produced by Node.js's own gyp build rather than a single library a generic tool could describe.
A non-CMake consumer has to link the archives, the externalized dependencies and the system
libraries by hand; the generated config is the readable description of that link line.

## Continuous integration

Five gates, described in `docs/ci.md`: a seconds-long lint pass on every push; a release-only
build of the port through `test/` on every push, across all six platform cells - both
architectures on Windows, Linux and macOS - blocking on x64 Windows and arm64 macOS and
non-blocking on the rest until each completes a build (x64 Linux reached that point on
2026-10-17); a weekly build of the Debug configuration,
which is off the push path because it costs roughly a full extra build per platform; a weekly
run of Node.js's own test suite; and a scheduled watcher that compares the pinned Node.js
version against `nodejs.org` and opens an issue when upstream moves, because nothing else will:
Renovate and Dependabot have no vcpkg manager. Every run's logs from every leg end up in a
single archive, and the run summary carries the test counts and the first error.

## Repository layout

| Path | Purpose |
|---|---|
| `ports/` | The overlay ports: `node` plus any dependency that has to be pinned or patched |
| `test/` | Consumer-side example project and the validation harness (ctest) |
| `tools/` | Maintenance scripts: the version-tree hasher, the hygiene checker, the release watcher |
| `versions/` | vcpkg version files (one per port), carrying each port's git-tree |
| `.github/workflows/` | Continuous integration; see `docs/ci.md` |
| `docs/` | Design notes, dependency disposition, build and CI reference |
| `docs/decisions/` | Architecture decision records |

## Documentation

- `docs/` — reference material, English, versioned with the code.
- `docs/decisions/` — why things are the way they are.
- `AGENTS.md` — working rules for this repository (useful for humans too).
- A full usage guide arrives with the first release.

## License

MIT — see `LICENSE`. Vendored and patched third-party code keeps its own license; the
corresponding NOTICE files are preserved.
