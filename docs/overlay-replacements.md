# Registry ports this repository replaces

Every directory under `ports/` is an overlay. When it carries a name that the registry also
has, declaring `overlay-ports` does not just give **node** that library: it gives the whole
dependency graph that library, and there is no per-port opt-out. This file is the disclosure
that goes with that behaviour, and `tools/check_repo.py` fails when a port exists without a
row here.

The versions on the right are what the registry ships at the pinned baseline
(`vcpkg 2026.07.29`, ADR 0003). "Graph gets" is what every consumer in the same manifest
receives.

| port | registry | graph gets | what changes for you |
|---|---|---|---|
| `libuv` | 1.52.1 | 1.52.1 plus Node.js's four backports (`unix/fs.c`, `uv-common.c`, `win/fs-event.c`, `win/tcp.c`) | same version, different source: the registry build does not carry Node.js's fixes. A consumer that links libuv gets Node.js's variant, not upstream 1.52.1 |
| `brotli` | 1.2.0 | 1.2.0 plus Node.js's `c/common/platform.h` | same version, one header different (IA64 target and `BROTLI_MODEL`/`BROTLI_COLD` guards) |
| `zlib` | 1.3.2 (madler) | Chromium fork, `1.3.2.1-motley` | compression behaviour and `process.versions.zlib` are Node.js's. **248 registry ports depend on zlib** and all of them get the fork. Evidence and accepted downside: `docs/zlib-fork.md` |
| `simdutf` | 8.2.0 | 8.2.0, built as **C++20** with `SIMDUTF_ATOMIC_REF` | same version, different ABI: V8 needs the atomic base64 entry points, which only exist in that configuration. A consumer that uses simdutf's C++ API must compile as C++20 too |
| `sqlite3` | 3.53.4 | 3.54.0 with `SQLITE_ENABLE_FTS3_PARENTHESIS` and `SQLITE_ENABLE_RBU` | newer minor than the registry, two extra features on. A consumer that links sqlite3 sees both |
| `simdjson` | 4.6.4 | 5.0.3 | major version jump; the C++ API between 4.x and 5.0 is not source compatible |
| `nghttp2` | 1.69.0 | 1.70.0 | minor version; the public header and the session/HPACK internals move (31 files differ), so the registry build is not the library Node.js is tested against |
| `llhttp` | 9.3.1 | 9.4.3 | minor version, generated parser included; a consumer that links llhttp sees the newer parser |
| `hdr-histogram` | 0.11.10 | 0.12.0 | minor version; the sources Node.js compiles differ from the registry's |
| `ada-url` | 3.4.4 | 4.0.0 | **major** version: Node.js ships 4.0.0 (its amalgamation reports `ADA_VERSION`), so a consumer that also links ada gets the 4.x API |
| `libffi` | 3.7.1 | 3.8.0 | minor version; ABI compatible |
| `mbedtls` | 3.6.5 | **4.0.0 development snapshot** | **breaking**: 4.0 splits the library (`libmbedcrypto` becomes `tfpsacrypto`) and changes APIs. LIEF 1.0.0's external branch requires 4.0 (`find_package(MbedTLS 4.0.0)`), so the graph cannot stay on 3.x while this port is consumed. A project that also uses mbedtls 3.x directly will not build against it |
| `frozen` | 1.2.0 | 1.2.0, commit `61dce5a` (post-1.2.0, 2025-07-29) | headers differ in six files; header-only, so a consumer only sees the difference if it relies on behaviour that changed |
| `tcb-span` | 2022-06-15 | same upstream commit plus a two-line no-exceptions `#include` fix | additive: the fix only makes the header compile with exceptions disabled |
| `lief` | 0.17.6 | 1.0.0 | major version jump (0.x to 1.0); the C++ and C APIs both moved. All of LIEF's own dependencies are separate vcpkg packages, so those still resolve to the versions listed here |
| `perfetto` | 53.0 | 58.2 | build-only for now: the node port does not wire `--shared-perfetto` (issue #12), so nothing links it unless you ask for it |
| `openssl` | 3.6.3 | 3.6.3, and on **Windows arm64 without assembly** (`VC-WIN64-ARM` + `no-asm`, Node.js's own configuration for that platform) | same version everywhere; the Windows arm64 binary is a different build of the same source. Issue #22: the baseline's assembly build (`VC-WIN64-CLANGASM-ARM`) crashes in 248 silent TLS cases on the arm64 leg, where the official Node.js binary - a no-asm build - crashes in none (run 39201696549). A consumer on Windows arm64 gets the no-asm library, which is what Node.js itself ships |
| `node` | - (not in the registry) | Node.js v26.12.0 built as a static library | not a replacement: the curated registry cannot host this port (V8 is a Node.js-maintained fork, so the tree is always built here). Listed because the check requires a row for every port |


## Why keep these overlays instead of waiting for the registry

The port's contract is that the delivered library behaves like the Node.js release it is built
from: same dependency versions where behaviour is observable, same compression, same unicode
handling, same TLS stack. The registry moves on its own schedule; the release notes for
each overlay are in `ports/<name>/vcpkg.json` and `docs/dependency-disposition.md`. Where the
registry is at or ahead of what the tree needs, this repository uses the registry port - the
overlay list is only the set of exceptions to that rule.
