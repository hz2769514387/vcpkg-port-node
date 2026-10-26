# Dependency disposition — Node.js v26.12.1 against vcpkg 2026.10.16

Every dependency Node.js carries, what vcpkg has, what was measured, and what we do about
it. This is the reference behind `ports/` and its overlay ports; keep it in step with them.

## 1. Decision rule

Node.js 26 can externalize most of its C/C++ dependencies through official channels:
`--shared-<lib>` (24 of them), `--shared-builtin-<module>-path` for JS/WASM, and
`--with-intl=system-icu` for ICU (note: ICU's channel is *not* named `--shared-icu`).

Given an externalize channel, the disposition follows from the version comparison:

| Case | Disposition |
|---|---|
| vcpkg version **>=** node version | Use the vcpkg port as-is. **Do not downgrade.** Carry Node.js's own patches on top if it has any. |
| vcpkg version **<** node version | Overlay port pinned to the version Node.js ships, plus Node.js's patches. |
| No vcpkg port | Vendor it (it comes from the Node.js source tree). |

There is a second, independent rule that protects consumers:

> **Anything compiled into the artifacts we ship must exist exactly once in a consumer's
> process.** Two copies of the same library, at the same or different versions, are
> unacceptable: identical COMDAT names get silently folded by the linker ("pick any"), so
> which implementation wins depends on link order. This is what moves `abseil`, `highway`,
> `simdutf` and `zlib` from "vendored" to "must be externalized" — see §4.

The version comparison is **transitive**. When a dependency Node pulls in carries
third-party dependencies of its own — LIEF is the case in point — the same rule applies
to those, with "node's version" read as *the version that dependency vendors*: vcpkg at
or ahead of it means the vcpkg port is used as-is (plus the dependency's own patches, if
any); vcpkg behind it means an overlay pinned to the vendored version. And because of the
exactly-once rule above, "leave it embedded in the dependency" is never an option: an
embedded copy would put a second version of the library into the consumer's graph the
moment the consumer links the vcpkg port of the same name. Watch the names, too — they do
not always match (LIEF's `expected` is `tl-expected`, a different library from the
registry's `expected-lite`). LIEF's own dependency set is dispositioned in §3.1.

## 2. How these numbers were produced

- **Node.js side**: the official `node-v26.12.0.tar.xz` release tarball (the same archive
  the port downloads and hash-pins). Versions were read from the source itself —
  `include/uv/version.h`, `VERSION.dat`, `zlib.h`, `include/LIEF/version.h`,
  `README.chromium`, `package.json` and so on — not from upstream documentation.
- **vcpkg side**: release 2026.07.29, commit `9e593bb18ea69cc5095e012465dcd675a822ed0d`,
  port versions read out of the release archive. Upstream sources come from the vcpkg
  download cache (the exact tarballs the pinned ports fetch).
- **Byte-level comparison**: `tools/compare_vendored.py` — file sets plus sha256 of
  contents. Example:

  ```sh
  python3 tools/compare_vendored.py \
      --node node-v26.12.0.tar.xz \
      --upstream /path/to/vcpkg/downloads/libuv-libuv-v1.52.1.tar.gz \
      --path deps/uv
  ```

- Numbers taken from research notes of the previous (Node.js 24) cycle are **not** reused
  unless re-verified here. Two claims did not survive re-verification and are called out in
  §3 and §5.

## 3. Version baseline

Versions measured from the Node.js v26.12.1 source tree. "vcpkg" is release 2026.10.16.

The *byte-level* comparisons quoted further down were measured against the 2026.07.29 / 26.12.0
pair. For the 2026.10.16 / 26.12.1 pair the versions were re-read and the three dependencies whose
bytes changed - c-ares (1.34.8 → 1.34.9), brotli (1.2.0 → 1.2.1) and zlib (unchanged) - were
compared again; the verdicts for the rest are carried over and are what the matrix re-checks in
practice. That is a weaker claim than the original pass and it is written down rather than implied:
re-running `tools/compare_vendored.py` against the new tarballs is worth an afternoon and not
required by this upgrade.

| Dependency | Node.js 26.12.1 | vcpkg | Channel | Version verdict |
|---|---|---|---|---|
| V8 | 14.6.202.34 | — | none | vendored (node fork, no `--shared-v8`) |
| openssl | 3.5.9 | 3.6.3 (registry has 3.6.5) | `--shared-openssl` | vcpkg ahead of Node.js, behind the registry → use vcpkg, refresh tracked in #29 |
| libuv | 1.52.1 | 1.52.1 | `--shared-libuv` | equal, node patches → overlay |
| c-ares | 1.34.9 | 1.34.8 | `--shared-cares` | **overlay at 1.34.9**: the registry is a patch release behind the tree, and 1.34.9 is part of 26.12.1's security content |
| brotli | 1.2.0 + CVE cherry-pick | 1.2.0 | `--shared-brotli` | **overlay at 1.2.1**: the registry's 1.2.0 does not carry CVE-2026-111497, which Node.js has and 1.2.1 fixes upstream; plus Node.js's `c/common/platform.h` |
| zstd | 1.5.7 | 1.5.7 | `--shared-zstd` | equal, sources match → use vcpkg |
| nghttp2 | 1.70.0 | 1.69.0 | `--shared-nghttp2` | vcpkg behind → `ports/nghttp2` pins 1.70.0 (overlay) |
| ngtcp2 | 1.25.0 | 1.25.0 | `--shared-ngtcp2` | equal; vcpkg port's TLS backends are opt-in features (none default-on) → use vcpkg port |
| nghttp3 | 1.18.0 | 1.18.0 | `--shared-nghttp3` | equal → use vcpkg port; its static lib devendors sfparse, so the link line carries `-lsfparse` too |
| sqlite3 | 3.54.0 | 3.53.4 | `--shared-sqlite` | vcpkg behind → overlay pin 3.54.0 |
| icu | 78.3 (icu-small) | 78.3 | `--with-intl=system-icu` | equal → use vcpkg (decision: full ICU) |
| llhttp | 9.4.3 | 9.3.1 | `--shared-http-parser` | vcpkg behind → `ports/llhttp` pins 9.4.3 (overlay) |
| simdjson | 5.0.3 | 4.6.4 | `--shared-simdjson` | vcpkg behind → overlay pin 5.0.3 |
| ada-url | 4.0.0 (amalgamation: `ADA_VERSION`) | 3.4.4 | `--shared-ada` | major version ahead → `ports/ada-url` pins 4.0.0 (overlay) |
| hdr-histogram | 0.12.0 | 0.11.10 | `--shared-hdr-histogram` | vcpkg behind → `ports/hdr-histogram` pins 0.12.0 (overlay) |
| LIEF | 1.0.0 | 0.17.6 | `--shared-lief` | vcpkg behind a major → overlay pin 1.0.0 |
| libffi | 3.8.0 | 3.7.1 | `--shared-ffi` | vcpkg behind → overlay pin 3.8.0 |
| perfetto | 58.2 | 53.0 | `--shared-perfetto` | overlay pin 58.2 (node-only, not V8) — **ready but not wired**, see below |
| zlib | 1.3.2.1-motley (Chromium fork) | 1.3.2 (madler) | `--shared-zlib` | different source → overlay port, built and measured: [zlib-fork.md](zlib-fork.md) |
| googletest | Chromium fork 1.8.0.git-9518a57 | 1.17.0 | `--shared-gtest` | test only → see §4 |
| V8: abseil | Chromium fork, rev `6d8e1a5c…` | 20260107.1 | `--shared-abseil` | different fork → issue #1 |
| V8: highway | Chromium fork, rev `8295336d…` | 1.4.0 | `--shared-highway` | different fork → issue #1 |
| V8: simdutf | 7.7.0 (single header) | 8.2.0 | `--shared-simdutf` | vcpkg ahead → issue #2 |
| V8: zlib | 1.3.2 | 1.3.2 | via `node_shared_zlib` | V8's own copy; must be gone ([zlib-fork.md](zlib-fork.md)) |
| uvwasi | 0.0.23 | — | `--shared-uvwasi` | no port → vendor |
| nbytes | 0.1.4 | — | `--shared-nbytes` | no port → vendor |
| merve | no version recorded | — | `--shared-merve` | no port → vendor |
| ncrypto | no version recorded | — | none | no port → vendor |
| postject | tool | — | `--shared-postject` | no port → vendor |
| inspector_protocol | rev `1b1bcbbe…` | — | none | tied to V8 → vendor |
| npm | 11.20.0 | — | `--shared-builtin-*` | JS ecosystem → vendor |
| undici | 8.11.2 | — | `--shared-builtin-*` | JS ecosystem → vendor |
| acorn | 8.18.0 | — | `--shared-builtin-*` | JS ecosystem → vendor |
| minimatch | 10.2.6 | — | `--shared-builtin-*` | JS ecosystem → vendor |
| amaro | 1.1.11 | — | none | WASM/npm → vendor |
| crates | Cargo manifest (V8 14.6.202) | — | none | cargo → vendor |

Two entries deserve a correction note:

- **abseil**: the previous cycle's research recorded V8's abseil revision as `6d5ac0f7`.
  The v26.12.0 tree says `6d8e1a5cf00d6a6b26069b0baf0dd9b855a17459`. Use the value measured
  here.
- **zlib**: node's `README.chromium` gives `Version: 1.3.2` with
  `Revision: 09a1572a…` — that revision describes the **upstream** madler tree the fork is
  based on, not a Chromium commit. `ZLIB_VERSION` in the tree is `1.3.2.1-motley`, with no
  commit suffix. Any statement about "the Chromium fork commit node pins" needs another
  source than this tree (§7).
- **perfetto** is the one row whose channel is deliberately left unwired. It is an opt-in
  embedder feature — Node.js's own release build does not pass `--with-perfetto`, so the
  default build compiles no perfetto at all (nothing to collide with). Turning it on hits
  a V8 gyp gap in the shared-SDK path: with `v8_use_perfetto=1` the GN-scraped source list
  drops `src/libplatform/tracing/trace-object.cc` from `v8_libplatform`, while legacy
  tracing members still emitted into `v8_libplatform` and `mksnapshot` reference
  `TraceObject::~TraceObject()`, so `mksnapshot.exe` fails to link with LNK2019/LNK1120.
  The `ports/perfetto` overlay is built and verified; wiring it needs that V8 build-system
  gap fixed first (tracked in issue #12).

### 3.1 LIEF's own dependencies (the rule applied transitively)

LIEF 1.0.0 can populate its third-party set with FetchContent from zips inside its own
source tree, and the vcpkg baseline's lief port (0.17.6) externalizes all of them. Per §1
neither route is acceptable unchanged: the baseline's port is the wrong version, and
FetchContent would embed copies that collide with the vcpkg ports. So every dependency is
externalized through LIEF's own `*_EXTERNAL` switches, each decided by the same version
comparison. "LIEF tree" is the version vendored inside Node.js v26.12.0's
`deps/LIEF/third-party/`; "vcpkg" is release 2026.07.29.

| Dependency | LIEF tree | vcpkg | Channel | Verdict |
|---|---|---|---|---|
| nlohmann json | 3.12.0 | 3.12.0 | `LIEF_OPT_NLOHMANN_JSON_EXTERNAL` | equal → registry port |
| spdlog | 1.17.0 | 1.17.0 | `LIEF_EXTERNAL_SPDLOG` | equal → registry port (LIEF requires exactly 1.17.0) |
| tl::expected | 1.3.1 | 1.3.1 | `LIEF_EXTERNAL_EXPECTED` | equal → registry port (**not** `expected-lite`, a different library) |
| utfcpp | 4.0.9 | 4.1.1 | `LIEF_OPT_UTFCPP_EXTERNAL` | vcpkg ahead → registry port, no downgrade |
| frozen | commit `61dce5a` (2025-07-29) | 1.2.0 (2024-06-02) | `LIEF_OPT_FROZEN_EXTERNAL` | vcpkg behind → overlay pin `61dce5a` (six headers differ) |
| tcb-span | commit `b70b0ff` | 2022-06-15 snapshot | `LIEF_EXTERNAL_SPAN_DIR` | vcpkg behind → overlay: same upstream commit as the baseline **plus** the no-exceptions include fix LIEF's tree carries (see below) |
| mbedtls | 4.0.0 snapshot `ec4044008d` (2025-10-13) | 3.6.5 | `LIEF_OPT_MBEDTLS_EXTERNAL` | vcpkg behind → overlay pin the snapshot. Required, not just policy: LIEF's external branch runs `find_package(MbedTLS 4.0.0)` and links `MbedTLS::tfpsacrypto` / `MbedTLS::mbedx509`, which only exist in the 4.0 line |

Two entries deserve a note:

- **frozen** is header-only and enabled whenever the compiler supports C++14 (always
  here). The delta between the v1.2.0 tag and LIEF's commit touches six headers, so the
  overlay pins the commit rather than trusting the release tag.
- **tcb-span**: LIEF builds its core library with exceptions disabled
  (`LIEF_DISABLE_EXCEPTIONS` defaults ON), which activates span's
  `TCB_SPAN_NO_EXCEPTIONS` branch. That branch calls `std::terminate()`, and the
  `#include <exception>` it needs exists only in LIEF's `b70b0ff` — a commit reachable
  from **no ref in tcbrindle/span** (verified against `git ls-remote` and the compare
  API), i.e. it lives only inside LIEF's vendored copy. The overlay therefore applies
  that two-line fix to the same upstream commit the baseline pins; upstream master today
  still lacks it.

## 4. What V8 compiles into the artifacts we ship

The question "is this library vendored or externalized" is only interesting when the
library actually produces symbols in the delivered package. Measured on v26.12.0 by
searching every `.gyp` / `.gypi` / `.gn` / `.gni` file in the tree:

| V8 third-party library | Referenced by build files | Compiled into our artifacts? |
|---|---|---|
| `abseil-cpp` | `tools/v8_gypfiles/abseil.gyp`, `v8.gyp`, `node.gyp`, `d8.gyp`, `v8_debug_helper.gyp` | **yes** |
| `highway` | `tools/v8_gypfiles/highway.gyp`, `v8.gyp`, `node.gyp` | **yes** |
| `simdutf` | `tools/v8_gypfiles/simdutf.gyp`, `v8.gyp`, `node.gyp`, `node.gypi`, `deps/ada/ada.gyp`, `deps/merve/merve.gyp` | **yes** (also used by ada and merve) |
| `zlib` | `tools/v8_gypfiles/v8.gyp` | **yes** |
| `fp16` | `v8.gyp`, `d8.gyp`, `v8_debug_helper.gyp` | header only, test tools only |
| `jsoncpp` | **only** `deps/v8/third_party/jsoncpp/BUILD.gn` (a GN file) | **no** — the gyp build never touches it |
| `fast_float`, `rapidhash-v8`, `dragonbox`, `wasm-api`, `utf8-decoder`, `re2` | none | **no** |
| `ittapi` | `v8vtune.gyp` only (not enabled) | no |
| `googletest` (V8's copy) | `deps/v8/third_party/googletest/**` (test targets) | no — test only |

So the externalize-or-die set is exactly four libraries: **abseil, highway, simdutf, zlib**.
That matches the previous cycle's shipped-artifact evidence, where the only libraries that
had to be moved into `lib/manual-link/` to avoid colliding with vcpkg ports were
`abseil`, `highway`, `v8_zlib` and `crdtp`.

`jsoncpp` is the counter-example worth remembering: vcpkg does ship `jsoncpp`, and many
ports depend on it, yet vendoring V8's copy cannot collide with a consumer's copy, because
no compiler ever sees it. **"Vendored" is not a risk by itself; producing the same symbols
twice is.**

## 5. Measured deltas (same version, different bytes)

`content differs` counts files present on both sides with different contents. "only
upstream" is mostly Node.js pruning documentation, tests and CI configuration; "only node"
is mostly gyp/GN build files, and sometimes generated headers Node.js checks in.

| Dependency | content differs | of which source/header | only upstream | only node | Reading |
|---|---|---|---|---|---|
| libuv 1.52.1 | 4 | 4 | 318 | 4 | Node.js carries four backports: `src/unix/fs.c`, `src/uv-common.c`, `src/win/fs-event.c`, `src/win/tcp.c`. Overlaying is mandatory to keep them. |
| brotli 1.2.0 | 1 | 1 | 57 | 3 | `c/common/platform.h` — Node.js's platform compatibility patch. |
| c-ares 1.34.8 | 1 | **0** | 212 | 37 | The only differing file is `.gitignore`. **No source differences.** Node.js checks in 11 generated headers (`config/*/ares_config.h`, `include/ares_build.h`) that vcpkg generates at build time instead — the values must be compared, not the files. |
| zstd 1.5.7 | 0 | 0 | 536 | 3 | Clean. |
| sqlite3 3.54.0 | 0 | 0 | 46 | 3 | Clean; Node.js ships the 6-file amalgamation. |
| ngtcp2 1.25.0 | 0 | 0 | 233 | 90 | Clean sources; Node.js adds `third-party/libev`, `third-party/urlparse` and a generated `version.h` for its own build. |
| zlib (Chromium fork) | 24 | 19 | 67 | 18 | 24 files differ and 18 more exist only in Node.js (the SIMD sources, `chromeconf.h`, `cpu_features.*`, `zlib.gyp`, `BUILD.gn`). The fork adds SIMD crc32/adler32 with runtime CPU detection and several inflate/deflate corrections upstream never merged. |
| nghttp2 1.70.0 vs 1.69.0 | 31 | 31 | 553 | 7 | The version gap is real: the public header and the session/HPACK internals all move. |
| llhttp 9.4.3 vs 9.3.1 | 3 | 3 | 1 | 3 | `include/llhttp.h`, `src/api.c`, `src/llhttp.c` (llhttp ships a generated parser). |
| simdjson 5.0.3 vs 4.6.4 | 0 common files | 0 | 740 | 5 | Node.js ships only the amalgamation (`simdjson.h`/`simdjson.cpp`) — but unlike ada's it **does** date itself: the generated header comment and `SIMDJSON_VERSION` both say 5.0.3, so the overlay pin is measured, not guessed. |
| ada-url (node amalgamation) vs 3.4.4 | 1 (README) | 0 | 192 | 6 | Same shape; the major-version gap needs an upstream 4.0.0 comparison. |

Not measured yet (no matching upstream tarball on hand): nghttp3, icu, hdr-histogram,
libffi, LIEF, perfetto, openssl, googletest, and the V8 third-party forks. Those rows are
marked "not measured" rather than guessed.

### 5.1 zlib: the in-tree patch series is not a recipe

`deps/zlib/patches/` holds 20 patch files (`0000-build.patch` … `0019-fix-zip64-in-zip.patch`)
plus a `README` explaining that they are generated with `git format-patch`. Applying them in
order onto the madler zlib 1.3.2 tarball **does not reproduce Node.js's tree**: hunks fail in
`contrib/minizip/ioapi.c`, `gzread.c` and `zconf.h`, and both `git apply` and GNU `patch`
classify some of the files as malformed (they are Chromium's bookkeeping against Chromium's
own mirror branch, not a cumulative series against the upstream release).

Consequence for the overlay port (issue #3): the port cannot be "madler tarball + these 20
patches". It must either pin Chromium's mirror repository at a commit, or vendor Node.js's
tree, and the choice needs a provenance source for the commit (§7).

## 6. Disposition summary

| Disposition | Dependencies |
|---|---|
| Use the vcpkg port as-is | openssl (3.6.3 > 3.5.9), icu (78.3), c-ares, zstd, nghttp3 (link sfparse alongside), ngtcp2 |
| Overlay: pin the version Node.js ships, add its patches | libuv, brotli, nghttp2, llhttp, simdjson, ada-url (+ simdutf feature), hdr-histogram, libffi, LIEF, perfetto, sqlite3 |
| Overlay: replace the upstream source entirely | zlib → Chromium fork (issue #3) |
| Externalize from V8's tree (the must-unify four) | abseil, highway (issue #1), simdutf (issue #2), zlib (issue #3) |
| LIEF's own third-party set — all externalized, none embedded (§3.1) | registry: nlohmann-json, spdlog, tl-expected, utfcpp; overlays: frozen, mbedtls, tcb-span |
| Vendor | V8; jsoncpp, fast_float, fp16, rapidhash, dragonbox, wasm-api, utf8-decoder, re2 (produce no symbols); googletest (test only); uvwasi, merve, nbytes, ncrypto, postject, inspector_protocol, temporal_capi (no vcpkg port); npm, undici, acorn, minimatch, amaro, crates (other ecosystems) |

## 7. Open verifications

The disposition above is only as good as the four measurements that remain. Each has an
issue with its acceptance criteria:

- **#1** `--shared-abseil` / `--shared-highway` against vcpkg's copies of the two forks.
- **#2** `--shared-simdutf` with vcpkg 8.2.0 against V8's 7.7.0 — and the version question
  between them, which the `ada-url` simdutf feature also depends on.
- **#3** The Chromium zlib fork as an overlay port (also: a provenance source for the fork
  commit).
- **#4** LIEF 1.0.0 C API compatibility.

Still to measure before any of this is called done:

- Byte-level deltas for nghttp3, icu, hdr-histogram, libffi, LIEF, perfetto, openssl.
- The real version of `ada-url` as Node.js ships it — its amalgamation carries no version
  string (simdjson's does: 5.0.3), so the planned overlay pin would otherwise be a guess.
- The `c-ares` generated headers: `config/*/ares_config.h` and `ares_build.h` as Node.js
  checks them in, against what vcpkg's CMake generates on each platform.
- `sqlite3` compile-time macro set versus the overlay's feature list.
