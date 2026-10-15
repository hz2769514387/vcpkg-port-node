# CI reference

What runs, where, and what each run actually proves. Every workflow lives in
`.github/workflows/`; anything about *why* the gates are shaped this way is in the ADRs, not
here ([0002](decisions/0002-node-version-policy.md), [0003](decisions/0003-vcpkg-baseline-policy.md),
[0004](decisions/0004-continuous-integration.md)).

## 1. The three gates

| Workflow | Trigger | Cost | Decides |
|---|---|---|---|
| `lint.yml` | push to `main`, pull request, manual | seconds | the repository still obeys its own rules: version files match the ports, tracked files are English/LF/UTF-8, referenced patches exist |
| `ci.yml` | push to `main`, pull request, manual | tens of minutes per platform | the port **builds and can be consumed**, and the fast assertions about it pass |
| `node-suite.yml` | weekly (Monday 03:17 UTC), manual | about an hour per platform | what was built is **still Node.js** |
| `node-release-watch.yml` | daily (06:23 UTC), manual | seconds | whether upstream has published a newer Node.js release (ADR 0002) |

`ci.yml` and `node-suite.yml` both call `.github/workflows/build-test.yml`, which is the only
place the build steps exist. They differ in one input: `ctest-options` is `-LE node-suite`
for the fast gate and `-R node-suite` for the slow one.

## 2. How a build is done

Nothing builds the port directly. Every leg checks out the pinned vcpkg (ADR 0003), bootstraps
it, and then configures `test/` — the consumer test project — which pulls the port in through
its manifest and builds it as an ordinary dependency. That is deliberate: a port that only
builds when driven in a special way is not a port, and CI should discover that first.

```sh
VCPKG_ROOT=<pinned checkout> cmake --preset windows      # also builds the port via vcpkg
cmake --build --preset windows
ctest --test-dir build/windows -C Release -LE node-suite --output-on-failure
```

Requirements the runner image has to satisfy, all of them failures that have happened at least
once: `cargo` (Node.js 26 builds its Temporal crate from Rust), `python3` (gyp, and the
official test driver), `clang-cl` on Windows (upstream requirement), and enough disk space.
The first three are checked in a step named *Toolchain inventory*; the last one is printed
before the build.

## 3. The matrix

| Runner | Preset | Triplet | Status |
|---|---|---|---|
| `windows-latest` | `windows` | `x64-windows-static` | measured — a failure here is a real failure |
| `ubuntu-latest` | `linux` | `x64-linux` | experimental (`continue-on-error`) |
| `macos-latest` | `macos` | `arm64-osx` | experimental (`continue-on-error`) |

Only Windows has ever been built end to end ([build.md](build.md), [test-suite-results.md](test-suite-results.md)).
The other two are in the matrix rather than absent because the port claims to support them:
leaving them red-but-non-blocking is how the claim stays honest instead of aspirational. They
stop being experimental when a full build plus a suite run passes on them.

Windows is deliberately the Visual Studio generator with an explicit `x64` architecture: the
default platform of a Visual Studio generator is Win32, and a `x64-windows-static` triplet
would then be asked for a Win32 build.

## 4. What the tests assert, and what they do not

- `smoke.*` — Node.js identity and provenance: the version the port claims, and whether every
  externalized dependency really came from vcpkg. See `test/smoke/externalization.mjs`.
- `node-suite.*` — Node.js's own suite through its own driver, with the **embedding
  executable** as the shell. That is the strongest available statement that libnode is a
  runtime and not just a library that links.

Neither replaces a symbol audit (two copies of one library in a single process is the failure
this repository exists to prevent) or a check that the delivered headers match the delivered
library. Those are tracked as work items, not skipped.

Skips live in `test/cmake/node-suite-skips*.txt` with a mandatory reason per entry, and the
symbol-link ones are applied only after probing whether this machine can create symlinks —
a permission, not a platform property.

## 5. Caching

`VCPKG_BINARY_SOURCES` defaults to `clear;x-gha,readwrite`, so the dependencies (OpenSSL, ICU,
…) are reused between runs. The port's own package is several gigabytes compressed, which is
a large share of the repository's 10 GB cache budget; if cache eviction starts hurting, pass
a different value through the `vcpkg-binary-sources` input of `build-test.yml`.

## 6. Release watch

`node-release-watch.yml` runs `tools/node_release_watch.py` once a day. The tool makes a
single request to `https://nodejs.org/dist/index.json`, compares the newest release of the
pinned line with `ports/node/vcpkg.json`, and makes sure exactly one open issue describes what
is available. Without a token it prints its finding and writes nothing, so it is safe to run
locally. A new *major* line is reported as a separate issue, because crossing one is a project
rather than a version bump.

## 7. What CI does not do

No tags, no releases, no publishing anywhere. The project is in its development period
(AGENTS.md, section 5), so `main` may be red and no interface is promised to consumers.
Releasing is the maintainer's decision.
