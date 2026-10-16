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
| `embedding/` | What embedding has to support beyond that: exit-code semantics, `worker_threads`, spawning a child process, and linking the port next to the very libraries it externalizes. |
| `smoke/` | Seconds. Node.js identity, and whether each externalized dependency really came from vcpkg. Runs on every push. |
| `official_suite/` | Node.js's own suite, through its own driver, labelled `node-suite`. Minutes to an hour. |
| `cmake/` | The suite driver and its skip lists. |

## Running it

```sh
export VCPKG_ROOT=/path/to/bootstrapped/vcpkg     # Windows: $env:VCPKG_ROOT = ...

cmake --preset windows      # or: linux, macos
cmake --build --preset windows
ctest --test-dir build/windows -C Release --output-on-failure
```

Stock triplets only: `x64-windows-static`, `x64-linux`, `arm64-osx`. With an unset
`VCPKG_BUILD_TYPE` the port builds Release **and** Debug, so a Debug consumer is possible;
the presets build the consumer as Release.

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
| `-DNODE_TEST_SKIP=test-foo` | One-off skips for a single run. Long-lived ones belong in `cmake/node-suite-skips.txt`, which requires a reason |

Fast runs skip the heavy label:

```sh
ctest --test-dir build/windows -C Release -LE node-suite --output-on-failure
```

## Skip lists

`cmake/node-suite-skips.txt` and `cmake/node-suite-skips-symlink.txt` are the single source
of truth, with one required reason per entry - a skip nobody can explain is a bug waiting to
be forgotten. The second file is applied only when probing shows this machine cannot create
symlinks, because that is a permission, not a platform property: it fails in a plain local
Windows shell and works with Developer Mode and in most CI images.

Neither file lists anything upstream already marks SKIP or FLAKY in its own `*.status` files:
the driver reads those, and duplicating them would freeze a decision that is upstream's to
change.
