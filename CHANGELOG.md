# Changelog

One entry per release tag: the same facts as that tag's GitHub Release body, kept here so the
repository reads without a network. Versions are dates — see
[docs/versioning.md](docs/versioning.md) for why, and for what the three numbers mean.

## 20261110 — Node.js 26.13.0, vcpkg 2026.10.16

`20261110_26.13.0_vcpkg-2026.10.16`

| | |
|---|---|
| Node.js | v26.13.0 (V8 14.6.202.34, `NODE_MODULE_VERSION` 147, napi 8, npm 11.20.0) |
| vcpkg | 2026.10.16 (`9eec002df1cd109f8f104cd966a763daf9751489`), pinned |
| port | `node` 26.13.0, `port-version` 4, 27 patches |
| verified by | CI 42735914269 (six Release cells with Node.js's own suite), Debug 42735914565 (four cells), Matrix 42735914275 (twelve cells) |

Everything since the `20261024` tag, in one release. A preparation that called itself `20261026`
was written but never tagged - `versions.json` claimed `released: true` for a tag that does not
exist, which is the defect #90 fixed - so its content ships here, beside the 26.13.0 work that
followed it.

### Node.js 26.12.1, a security release

Three of its fixes are in libraries this port *externalizes*, so upgrading Node.js alone would
have left the delivered library vulnerable to the very CVEs the release is about:

- **brotli** — CVE-2026-111497, fixed upstream in 1.2.1 and cherry-picked by Node into its 1.2.0.
  The overlay ships 1.2.1, with the Node.js `c/common/platform.h` patch regenerated against it.
- **c-ares** — the release moves to 1.34.9; vcpkg 2026.10.16 still ships 1.34.8, so `ports/c-ares`
  is an overlay at 1.34.9. Without it the port would deliver a c-ares older than the release it
  claims to package.
- zlib's fix (invalid ZIP local headers) is in Node.js's own code, not in the fork this port
  overlays.

### vcpkg 2026.10.16

The registry moves to the versions Node.js v26.12.1 vendors for the dependencies that matter most
here: libuv 1.52.1, nghttp2 1.70.0 and ngtcp2 1.25.0 all match the tree exactly, where 2026.07.29
was behind on two of them. What the upgrade found, and fixed:

- utfcpp 4.2 removed `internal::validate_next(it, end, cp)`, which LIEF 1.0.0 calls, so
  `ports/utfcpp` pins 4.1.1 - same major, same target, same layout.
- The exported package version was a literal and said 26.12.0 while delivering 26.12.1. It now
  comes from `src/node_version.h` and is compared against the manifest.
- `ports/openssl` is re-derived from the new baseline's portfile (3.6.5) rather than the 2026.07.29
  one (3.6.3), which is what issue #29 tracked.

### Node.js 26.13.0, and the compiler the tree is built with

The LTS transition. It also changed how the Windows graph is compiled: **ICU is built with clang-cl
on every Windows triplet** (#27) - the previous configuration aborted inside ICU's own destructor
in a Windows x64 Debug consumer - and `ports/vcpkg-make` learned to drive a clang-cl triplet, so
make-based ports build with the compiler Node.js itself uses (ADR 0012). Four matrix cells now
build the whole graph that way, and they block a merge (ADR 0013).

### The consumer-facing surface

The exported config is a template rather than CMake emitted from strings, its version comes from
the tree it actually delivers, and `COMPATIBILITY SameMajorVersion` replaces `AnyNewerVersion` - a
27.x install can no longer satisfy `find_package(unofficial-node 26)`, because `NODE_MODULE_VERSION`
changes with every major line. A dependency the config names but the install lacks is now reported
by name instead of as "outside this install prefix". The package installs what the config tells a
consumer to link, not what gyp happened to build (#63). `usage`, the four consumer recipes and the
presets document both linkages.

### What the suite found

`process.execve` crashes with `SIGBUS` under Rosetta 2 on the x64 macOS cell, on a different member
of the same family from run to run - five are now skipped there, each with the official binary's
behaviour recorded beside it, because the official binary crashes a sibling on the same image. Two
other things were fixed rather than skipped: the suite now runs through a POST_BUILD copy named
`node`, which is the name upstream's tests assume (a `--trace-warnings` hint and one snapshot case
depended on it), and the symlink capability probe asks node in the tree the cases use instead of
python in `%TEMP%` (#32). `sequential/test-watch-mode.mjs` is skipped on the x64-osx *shared* cell
only (#28).

### Repository discipline

The build cells now run only when a change can affect the build (ADR 0010), which is what made the
review sweep affordable; the vcpkg cache key no longer changes when a port is edited; and the checks
grew from "the version files match" to: every portfile reference resolves, the patch list is read
from the directory it lives in, the overlay table matches the manifests, no overlay is behind both
the registry at the pin and the Node.js tree (#77), the release-only triplets match the stock ones
at the pin, and workflow scripts parse as shell. `tools/ci_watch.py` watches a run instead of a page.
The `perfetto` overlay is withdrawn (#88) - it is not a dependency of this port - so overlaying
replaces **20** registry ports, not 21. `README.zh-CN.md` is the one translated file, and
`tools/check_repo.py` holds the allowlist that keeps it the only one.

### Limits, as of this tag

ICU in a Windows x64 Debug consumer is no longer a limit - the clang-cl ICU build is what removed
it. Still not verified, and unchanged: **Linux arm64 Debug** (the dual install does not fit six
hours on a four-core runner, #26; neither Linux cell has a Debug leg, and `docs/ci.md` §3 records
why), and the documented limits in README are otherwise the same table.

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
