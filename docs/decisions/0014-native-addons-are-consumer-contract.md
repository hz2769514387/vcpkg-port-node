# 0014 - Consumer-built native addons are part of the embedding contract

Status: Accepted
Date: 2026-11-11

## Context

The port delivers Node.js as a library an application links, not as `node.exe`. A product
that embeds that library still loads `.node` modules: device drivers, codecs, database
clients and anything built with node-addon-api. Those modules contain `napi_*` calls they do
not define themselves.

Upstream `node.exe` exports those symbols from its own image and ships an import library for
addons to link. An embedding executable is a different image. With a static libnode the
`napi_*` implementation sits in the archives the host linked, and Windows does not export a
symbol from an executable unless it is asked to. The application then works perfectly while
its first addon fails to load with "The specified procedure could not be found" - a failure
that names neither the port nor the missing property.

Before this decision nothing in `test/` built an addon. The official Node.js suite runs
against the embedder, but its default suite list does not include `addons`, so the gap was
invisible to CI. `docs/overlay-replacements.md` and the exported `usage` describe the link
line for C++ consumers; neither said anything about addons.

Measured on the pinned Windows static install: the port's own `node.exe` exports 147
`napi_*` symbols; a consumer executable built with CMake's `ENABLE_EXPORTS ON` exports the
same 147; and a raw N-API MODULE linked against that executable loads and runs. Without the
property the link succeeds and the load fails. (`if(TARGET unofficial::node::libnode)` is
not a usable linkage test: CMake reports that namespaced name as an existing target on a
static install too, once `find_package(unofficial-node)` has loaded a config mentioning it.
Measured on CMake 3.31.)

## Decision

Loading a consumer-built N-API addon into the embedding executable is a supported use of the
port, on both static and shared installs, and is a CI-verified guarantee.

- `test/cases/embed` sets `ENABLE_EXPORTS ON` on the example executable - the shape a product
  copies. With a shared libnode the symbols come from the DLL instead and the property is
  harmless.
- `test/cases/addon` builds a real N-API module from the installed headers and loads it. It
  asserts the headers' `NODE_MODULE_VERSION` against the runtime, then exercises sync calls,
  JS callbacks, Buffers, thrown errors, async work on libuv's thread pool and a thread-safe
  function fed by a `std::thread`.
- `docs/consumer-recipes.md` §7 states both link shapes and the `NODE_PORT_SHARED` switch.
- The rest of the expanded test suite tests consumer behaviour rather than startup: a real
  application's module graph and CLI, shutdown semantics, the builtin modules that reach the
  externalized dependencies, repeated and concurrent environments, a loop signalled by a
  native thread, and the exported config's own contract.

Node.js's official suite stays in place. It answers "is this still Node.js"; these cases
answer "can a product use it". Both are needed, and neither substitutes for the other.

## Consequences

- Every build cell pays for one more MODULE target and a few more seconds of ctest. The
  Windows link of the example executable now carries an export table; measured on the local
  static install this costs seconds, and the resulting export table has the same 147
  `napi_*` names as upstream's executable.
- On Windows the addon links the executable for a static install and
  `unofficial::node::libnode` for a shared one. A new linkage shape has to be reflected in
  `cases/addon/CMakeLists.txt`, or the case fails at build time.
- Addon authors still need `BUILDING_NODE_EXTENSION` so `node_api.h` declares `napi_*` as
  `dllimport`; that is a property of their own build, not something the port can set for
  them.
- This ADR does not extend the promise to V8-API (non-N-API) addons. Those link against V8
  internals whose visibility is a separate question, and no case here claims otherwise.
