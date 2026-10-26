# Changelog

One entry per release tag: the same facts as that tag's GitHub Release body, kept here so the
repository reads without a network. Versions are dates — see
[docs/versioning.md](docs/versioning.md) for why, and for what the three numbers mean.

## 20261024.1 — Node.js 26.12.1, vcpkg 2026.10.16

`20261024.1_26.12.1_vcpkg-2026.10.16`

| | |
|---|---|
| Node.js | v26.12.1 (a security release: 10 CVEs; V8 14.6.202.34, `NODE_MODULE_VERSION` 147, napi 8, npm 11.20.0) |
| vcpkg | 2026.10.16 (`9eec002df1cd109f8f104cd966a763daf9751489`), pinned |
| port | `node` 26.12.1, `port-version` 0 (reset by the upstream bump), 25 patches |

Two bumps in one release, and one of them is the reason the other is not optional.

**Node.js 26.12.1** is a security release. Three of its fixes are in libraries this port
*externalizes*, so upgrading Node.js alone would have left the delivered library vulnerable to
the very CVEs the release is about:

- **brotli** — CVE-2026-111497, fixed upstream in 1.2.1 and cherry-picked by Node into its 1.2.0.
  The overlay now ships 1.2.1, regenerating the Node.js `c/common/platform.h` patch against it.
- **c-ares** — the release moves to 1.34.9; vcpkg 2026.10.16 still ships 1.34.8, so `ports/c-ares`
  is now an overlay at 1.34.9. Without it the port would deliver a c-ares older than the release
  it claims to package.
- zlib's fix (invalid ZIP local headers) is in Node.js's own code, not in the fork this port
  overlays.

**vcpkg 2026.10.16** moves the registry to the versions Node.js v26.12.1 vendors for the
dependencies that matter most here: libuv 1.52.1, nghttp2 1.70.0 and ngtcp2 1.25.0 all now match
the tree exactly, where 2026.07.29 was behind on two of them.

**Not in this release, on purpose:** `ports/openssl` is still derived from the 2026.07.29 port
(3.6.3) while the new baseline ships 3.6.5. It is a whole portfile rather than a version line, and
folding a portfile re-derivation into an upgrade would make three questions answerable by one
failing leg. Tracked in issue #29, with the argument for why the current state is not a live
vulnerability (Node.js 26.12.1 bundles OpenSSL 3.5.9; the overlay is ahead of it, behind the
registry).

## 20261024 — first release

`20261024_26.12.0_vcpkg-2026.07.29`

| | |
|---|---|
| Node.js | v26.12.0 (V8 14.6.202.34, `NODE_MODULE_VERSION` 147, napi 8, npm 11.20.0) |
| vcpkg | 2026.07.29 (`9e593bb18ea69cc5095e012465dcd675a822ed0d`), pinned |
| port | `node` 26.12.0, `port-version` 16, 27 patches |
| verified by | CI run 40025248541, Debug run 40025248583, Matrix run 40025248617 |

What this is: a vcpkg port that builds Node.js v26.12.0 from its own source tree with a clang-cl
or gcc/clang toolchain, delivers it as a static or shared library with a CMake config, and proves
it by running Node.js's own test suite against a consumer built through the public path.

**Verified cells.** Six Release cells (Windows x64/arm64, Linux x64/arm64, macOS arm64/x64) with
the suite on every one; five Debug cells (the same minus Linux arm64); eight matrix cells (the
dynamic CRT on Windows and a shared libnode everywhere). All green on the commit above.

**What is not verified, and is documented as such.** Linux arm64 Debug (the dual install does not
fit GitHub's six-hour job, issue #26); ICU date formatting in a Windows x64 Debug consumer (aborts
in ICU's own destructor, issue #27, README known limits); one intermittent suite case on the
x64-osx shared cell (issue #28).

**Benchmark** (release checklist step 5): against the official binary of the same version on the
shared Linux cell, [run 40063990752](https://github.com/hz2769514387/vcpkg-port-node/actions/runs/40063990752) —
OpenSSL identical, gzip 11% faster (chromium's zlib fork rather than madler), startup 16% slower
because that cell delivers a *shared* libnode, and V8's JSON and the buffer paths within a few
percent. The table is in the run's summary.

**Upstream already moved on.** Node.js v26.12.1 and vcpkg 2026.10.16 were published while this was
being finished (issues #24, #25). Both are routine bumps on `main` in the maintenance period, each
with its own full matrix run.
