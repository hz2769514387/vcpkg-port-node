# The zlib overlay port: the Chromium fork Node.js ships

Node.js does not use madler zlib. `deps/zlib` is the Chromium fork - `ZLIB_VERSION`
`1.3.2.1-motley` - with CPU-dispatch optimizations for adler32, the inflate chunk copy and
deflate's slide hash, plus inflate/deflate corrections Chromium and oss-fuzz produced and
upstream never merged. This repository's zlib is that fork, built as an overlay port
(`ports/zlib/`), because Node.js's behaviour is the reference it is held to.

The decision is issue #4's; this document is the evidence it asked for.

## 1. Source and provenance

| | |
|---|---|
| Repository | `https://chromium.googlesource.com/chromium/src/third_party/zlib` |
| Commit | `456ae730017b9b4bd3371927abc82627fd51feef` |
| Version string in the tree | `1.3.2.1-motley` |
| Fetch | `vcpkg_from_git`, `REF` = the commit (the repository is ~2.8 MB, so a shallow fetch by SHA is cheaper than an archive download and does not depend on archive bytes staying stable) |

The commit is the one Node.js v26.12.0 ships, established by content rather than by a version
field: `deps/zlib/README.chromium` records `Version: 1.3.2` with a `Revision:` that belongs to
madler's repository, not to the fork, so it cannot be used as a pin. Comparing the checked out
fork against node's `deps/zlib` file by file:

| | |
|---|---|
| files identical | 140 |
| files differing | 1 - `zconf.h`, which is generated from `zconf.h.in` by the build |
| files only in the fork | 54, essentially all of `contrib/`, which node prunes |
| files only in node | 2 - `zlib.gyp` and `win32/zlib.def`, node's own build inputs |

## 2. What the fork actually is, against madler 1.3.2

Byte-level comparison of the fork's tree against madler's 1.3.2 sources:

| | |
|---|---|
| files in the fork | 195 |
| files in madler 1.3.2 | 262 |
| identical | 30 |
| **differing** | **29**, of which 22 are library sources at the root (`adler32.c`, `compress.c`, `crc32.c`, `deflate.c`, `inflate.c`, `inftrees.c`, `trees.c`, `zutil.c`, `zlib.h`, `zconf.h`, ...) |
| only in the fork | 136 (43 under `contrib/`) |
| only in madler | 203 (madler's CI configs, MSVC project files, extra docs and test trees) |

The fork's own root-level additions are exactly the CPU-dispatch machinery and Chromium build
metadata: `adler32_simd.{c,h}`, `crc32_simd.{c,h}`, `crc_folding.c`, `compare256.h`,
`slide_hash_simd.h`, `cpu_features.{c,h}`, `chromeconf.h`, `README.chromium`, `BUILD.gn`,
`DIR_METADATA`, `OWNERS`.

### 2.1 Node.js does not enable all of it

`node/deps/zlib/zlib.gyp` turns on adler32 (SSSE3 or NEON), the inflate chunk copy
(`INFLATE_CHUNK_SIMD_SSE2`/`_NEON`) and `DEFLATE_SLIDE_HASH_SSE2`/`_NEON`, and it
**deliberately leaves the crc32 SIMD switched off**:

```python
'dependencies': [
  'zlib_adler32_simd',
  # Disabled due to memory corruption.
  # See https://github.com/nodejs/node/issues/45268.
  # 'zlib_crc32_simd',
],
```

That matters for this port in two ways. The define set a consumer gets must be Node.js's, not
Chromium's - a port that exists to be the zlib Node.js ships must not turn on what Node.js
refuses to build. And a Windows build must be possible at all: the fork's CMakeLists gates all
of this behind `ENABLE_SIMD_OPTIMIZATIONS`, which defaults to **OFF**, and its x86 branch tests
`CMAKE_SYSTEM_PROCESSOR STREQUAL "x86_64"`, which is never true on Windows (CMake says
`AMD64`). Left alone, that produces a zlib with no SIMD - and a build failure before that,
because `contrib/optimizations/chunkcopy.h` errors out when no chunk SIMD define is present.

## 3. The port

Derived from the pinned baseline's `zlib` portfile so that the layout consumers already expect
(static/dynamic, debug suffixes, pkg-config, the exported `ZLIB::ZLIBSTATIC` config) is
unchanged: the overlay's installed file list is identical to the registry port's.

Four patches, each for a reason that is written in it:

| Patch | Why |
|---|---|
| `0001-no-version-script-on-ohos.patch` | Carried over from the baseline unchanged - re-validated against the fork rather than copied blind: it applies as-is. |
| `0002-do-not-build-the-benchmark-unless-testing.patch` | The fork's benchmark target links the *shared* library by name, so a static-only build gets a target that does not exist and no include directories. Chromium builds this tree from GN, where the shared library is always there; a distribution-style build has to survive the static configuration. |
| `0003-simd-settings-node-uses.patch` | Makes the SIMD branch work on Windows and uses Node.js's define set: `AMD64` is accepted, `X86_WINDOWS` is defined there, the crc32 SIMD stays off, and `-pthread` is not passed to a compiler that has no such flag. |
| `0004-plain-system-zlib-names.patch` | Removes the unconditional `chromeconf.h` include from the public `zconf.h`, so the library is built - and its headers read - with the plain symbol names (`deflate`, `inflate`, `adler32`, ...). See below. |

### 3.1 Why plain names, not the `Cr_z_` prefix

`chromeconf.h` renames every zlib symbol to a `Cr_z_` prefix. Inside Chromium that is load
balancing for the component build: the prefixed symbols cannot collide with a system zlib in
the same process. A package manager's zlib is in the opposite position - it *is* the system
zlib, and the 248 registry ports that link `zlib` all call the plain names, as does V8's own
wiring in this repository (`ports/node/patches/0012` compiles V8 against the external zlib
and deliberately defines `CHROMIUM_ZLIB_NO_CHROMECONF` so V8 calls the plain names).

An earlier iteration of this port kept the include and installed `chromeconf.h` beside
`zconf.h`, shipping a `Cr_z_`-prefixed library. That library cannot be linked by anything
that calls zlib by its normal names - demonstrated, not assumed: building node against it
failed in `mksnapshot.exe` with `LNK2019` on `adler32`, `deflate`, `inflate`, ... A header
pair that only works when every consumer remembers to define
`CHROMIUM_ZLIB_NO_CHROMECONF` is not installable, so the prefix has to go in the artifact
itself, which is what patch 0004 does. The fork's own escape-hatch define still exists in
V8's patch; against the patched header it is a no-op safeguard rather than a requirement.

The port also asserts what it built: after install it reads `ZLIB_VERSION` out of the installed
`zlib.h` and fails unless the string contains `motley`. A port that quietly built madler's zlib
while claiming to be the fork is worse than either library, because nothing in the build output
would say so.

## 4. Measured

`x64-windows-static`, this machine, vcpkg at the pinned baseline, `--editable` (a real build,
not a cache restore). Port build: 10 s; `zlibVersion()` in a consumer that links it:
`1.3.2.1-motley`; a compress/uncompress round trip over 44 bytes returns the input and
`crc32 = c81637a1`.

### 4.1 Throughput

Throughput, same benchmark source and the same compiler flags, 32 MiB of compressible data,
four passes per call, medians of three runs:

| | registry zlib (madler 1.3.2) | fork, SIMD off | fork, SIMD on (**this port**) |
|---|---|---|---|
| adler32 | 3324.7 MiB/s | 3265.6 MiB/s | 3332.6 MiB/s |
| crc32 | 5382.2 MiB/s | 5134.0 MiB/s | 5422.9 MiB/s |
| deflate | 35.5 MiB/s | 46.8 MiB/s | **50.4 MiB/s** |
| inflate | 303.3 MiB/s | 319.7 MiB/s | **373.6 MiB/s** |

Read as: the fork is **+42 % deflate and +23 % inflate** over madler, and the SIMD defines
account for about **+9 % deflate and +17 % inflate** of that on their own. adler32 and crc32 are
level - expected, since Node.js keeps crc32 without SIMD and madler's scalar adler32 is already
fast on this data. All four checksums are identical between the libraries, which is the part
that says the two agree on results and not only on speed.

### 4.2 One input, both paths (criterion 4)

The benchmark says the fork is fast; it does not say the fork and node's compression path are
the same library, and a version string cannot say that either - two zlibs in one process can
report the same version. `test/zlib/` closes that: 256 KiB of deterministic input goes through
zlib's C API (`compress2`, level 6) and through node's `zlib.deflateSync` (level 6), and each
side inflates what the other produced. The runtime is `test/cases/embed`, the runtime a host
application links - not the port's own `node.exe`.

Measured, `x64-windows-static`:

| | |
|---|---|
| C API | `1.3.2.1-motley`, 262144 -> 169304 bytes, `crc32 = c8d24a46` |
| runtime (`process.versions.zlib`) | `1.3.2.1-motley` |
| runtime inflates the C API's output | byte-identical to the input |
| C API inflates the runtime's output | size matches, byte-identical to the input |
| crc32, computed by both | `c8d24a46` |
| the two deflate outputs | byte-identical (169304 bytes each) |

The deflate outputs being byte-identical is stronger than the check requires - sharing a library
is not the same as sharing a code path - so `zlib_paths.js` reports it as a note rather than
failing on it. What the check asserts is the part that would break if the overlay stopped being
used: both sides name the fork, each side recovers the other's output, and the checksums agree.
`test/embedding/coexist` covers the other half of the criterion - node and the other
externalized libraries (abseil, highway, simdutf, OpenSSL, zlib) linked into one process, each
called.

## 5. Blast radius

The registry has 248 ports that depend on `zlib`, and an overlay replaces the library for all of
them, not only for node. Two consequences, both accepted deliberately:

* Every consumer's ABI hash changes, so they rebuild on the first install after the overlay is
  picked up. That is a one-time cost per machine.
* Those consumers get the fork - a library with different source, more optimizations and a
  `motley` version string - without having asked for it.

The mitigation is that the fork is *tested as a general-purpose zlib*, not only as node's. Two
consumer-side tests stand in for the graph: `test/embedding/coexist` links node together with
the other externalized libraries and calls each in one process, and `test/zlib/` pushes the
same input through node's compression path and through the C API and checks both directions
(section 4.2). Neither enumerates the 248 ports; what they establish is that the fork behaves
as a zlib for consumers that are not node, which is the property the graph relies on.

## 6. Node.js on the overlay, and only one zlib

Node.js builds against this port and the process holds one zlib, not two. `config.gypi` records
`node_shared_zlib: "true"`, so node's own `deps/zlib` is not compiled - the check below is what
turns that flag into a fact.

V8 vendors the same fork under `deps/v8/third_party/zlib`, and its `v8_zlib` target built all of
it before this port existed. Patch `0012` removes the implementation sources from that target,
leaving only `compression_utils_portable.cc` - Chromium's wrapper, which V8's own code calls and
which is not the library - and defines `CHROMIUM_ZLIB_NO_CHROMECONF` so V8 calls the plain
symbol names. `v8_zlib.ninja` confirms the result: one compile step, the wrapper, a 23 KiB
archive.

The port does not take that on trust. After each configuration builds,
`ports/node/scripts/check_no_vendored_build.py` reads gyp's ninja output and fails the build if
any source under `deps/zlib` or `deps/v8/third_party/zlib` is compiled; the wrapper under the
latter's `google/` is the one deliberate exception, because it is the adapter, not the library.
The check knows the three shapes a source takes in gyp's ninja output - including the
`    cxx ..\..\<src>` shape that `v8_zlib.ninja` itself uses, which a check that only knew the
long-form continuation line would read past.

The official suite's zlib cases pass unchanged: 92 of 92, across `parallel/test-zlib*`,
`sequential/test-zlib-crc32-fast-api`, `pummel/test-zlib-zip-slow` and
`pummel/test-heapdump-zlib`, with no new skip entry.

## 7. Not done yet

* `x64-windows-static`, `x64-linux` and `arm64-osx` are all built by CI now, so the ARM64 SIMD
  branch has been exercised - on macOS, where the branch sets `ARMV8_OS_MACOS`. Windows ARM64 is
  the untested one: CMake spells the architecture `ARM64` there, upstream's branch only knows the
  POSIX spellings, so patch 0005 rewrites that branch for MSVC and CI has not confirmed it yet.
* The dynamic-linkage configuration - `zlib` built as a DLL and node linking that - is untested;
  everything measured above is the static configuration.
