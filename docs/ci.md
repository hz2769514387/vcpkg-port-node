# CI reference

What runs, where, and what each run actually proves. Every workflow lives in
`.github/workflows/`; anything about *why* the gates are shaped this way is in the ADRs, not
here ([0002](decisions/0002-node-version-policy.md), [0003](decisions/0003-vcpkg-baseline-policy.md),
[0004](decisions/0004-continuous-integration.md),
[0005](decisions/0005-vcpkg-pin-without-a-manifest-baseline.md)).

## 1. The gates

| Workflow | Trigger | Cost | Decides |
|---|---|---|---|
| `lint.yml` | push to `main`, pull request, manual | seconds | the repository still obeys its own rules: version files match the ports, tracked files are English/LF/UTF-8, referenced patches exist |
| `ci.yml` | push to `main`, pull request, manual | tens of minutes per leg | the port **builds and can be consumed** as a Release consumer, and the fast assertions about it pass |
| `debug.yml` | weekly (Monday 04:47 UTC), manual | about an hour per leg | the same, for the **Debug** configuration |
| `node-suite.yml` | weekly (Monday 03:17 UTC), manual | about an hour per leg | what was built is **still Node.js** |
| `node-release-watch.yml` | daily (06:23 UTC), manual | seconds | whether upstream has published a newer Node.js release (ADR 0002) |

The build-and-test workflows all call `.github/workflows/build-test.yml`, which is the only
place the build steps exist. They differ in which `preset`, `triplet` and `config` they pass,
in `ctest-options` (`-LE node-suite` for the fast path, `-R node-suite` for the suite), and in
whether a leg is blocking. Each of them also ends with a job that calls
`.github/workflows/logs.yml`, which merges every leg's logs into **one** archive per run
(section 6) - reading a run is one download, not one per platform.

## 2. How a build is done

Nothing builds the port directly. Every leg checks out the pinned vcpkg (ADR 0005),
bootstraps it, and then configures `test/` - the consumer test project - which pulls the port
in through its manifest and builds it as an ordinary dependency. That is deliberate: a port
that only builds when driven in a special way is not a port, and CI should discover that
first.

```sh
VCPKG_ROOT=<pinned checkout> cmake --preset x64-windows-static \
    -DVCPKG_TARGET_TRIPLET=x64-windows-static-release -DCMAKE_BUILD_TYPE=Release
cmake --build --preset x64-windows-static --config Release
ctest --test-dir build/x64-windows-static -C Release -LE node-suite --output-on-failure
```

Requirements the runner image has to satisfy, all of them failures that have happened at least
once: `cargo` (Node.js 26 builds its Temporal crate from Rust), `python3` (gyp, and the
official test driver), `clang-cl` on Windows (upstream requirement), and enough disk space.
They are reported by a step named *Toolchain inventory*; the disk is printed before the build.

### 2.1 One configuration per leg

`VCPKG_BUILD_TYPE` can only be set in a triplet, and leaving it unset makes the port build
Release **and** Debug - two Node.js builds per leg. That is what pushed the Linux leg past the
five-hour job limit. The push legs therefore name vcpkg's own **community** `*-release`
triplets - `x64-windows-static-release`, `arm64-windows-static-release`, `x64-linux-release`,
`arm64-linux-release`, `arm64-osx-release`, `x64-osx-release` - which are the standard
settings plus `VCPKG_BUILD_TYPE release`. vcpkg ships them, so this repository carries no
triplet file, and a consumer can name them too without copying anything.

`debug.yml` instead installs the *stock* (dual) triplet and builds the consumer as Debug,
because a debug-only triplet is not usable: seven ports in this port's dependency closure
(brotli, c-ares, libuv, ngtcp2, openssl, zstd, and this repository's own zlib overlay) run
post-install fixups against the non-debug layout and fail there. The measurements are in
issue #11.

The reason release is the push configuration rather than debug is that the two cost nearly the
same (measured 2026-10-15: Release 25m16s, Debug 27m38s for the same build on one machine) and
release is the layout vcpkg's own ports are written for. Debug is still verified - just off the
push path, where its cost does not hold up every commit.

### 2.2 The architecture assertion

Every Windows and macOS leg passes `expect-arch`, and `build-test.yml` checks the built
executable against it before running any test - the PE machine word on Windows, the Mach-O
description on macOS. That is not decoration: an arm64 Windows runner executes x64 binaries
through emulation, and an arm64 macOS runner executes x86_64 binaries through Rosetta. A build
that silently produced the wrong machine type would therefore run perfectly and pass every
ctest case while proving nothing. The check reads the file itself rather than calling
`dumpbin`, so it still works after an earlier step has broken the environment.

### 2.3 Guards absorbed from the node24 line

Three failures the previous line hit, each fixed here up front because the symptom is far from
the cause:

- **A CMake 4, installed when the image's is older.** vcpkg's scripts call
  `string(JSON ... STRING_ENCODE)`, which only exists from CMake 4, and some runner images still
  ship 3.31 - `ubuntu-24.04-arm` did, and died on the *first* dependency (abseil) with
  "invalid mode 'STRING_ENCODE'", which reads like a port bug rather than an image problem. The
  step installs a pinned CMake 4.4.0, matched to the runner's architecture, only when the CMake
  already on PATH is older. Two details are load-bearing: the version is read out of a variable
  rather than through a pipeline into `head` (under `pipefail`, `head` closing the pipe early
  can kill the writer with SIGPIPE and fail the step on a perfectly good CMake), and an arm64
  runner gets the arm64 asset rather than an x86_64 CMake under emulation.
- **Rosetta 2 on macOS x64.** The port builds its host tools as the *target* machine type too
  (Node.js's `--no-cross-compiling` path), so on an arm64 image the build and its tests execute
  x86_64 binaries. GitHub's arm64 images do not guarantee Rosetta, so the capability is probed
  through `arch -x86_64 /usr/bin/true` and installed if missing - otherwise the failure reads
  "Bad CPU type in executable".
- **Retrying only download failures.** vcpkg has no retry of its own for a source tarball, and
  one timeout from an upstream mirror costs the whole leg. The configure step retries, but only
  when the failure looks like a download problem *and* carries no build error: matching the word
  "download" alone is not enough, because the log quotes absolute paths such as
  `.../vcpkg/downloads/<archive>`, so a plain build failure matches it too and would then be
  retried four times at full wall-clock cost.
- **The Rust standard library for the target architecture.** The port builds Node.js's Rust
  crates with `cargo --target <triple>`, and a rustup toolchain ships the standard library for
  the architecture it was installed for - which on an x64-osx leg is not the one the triplet
  asks for. Without it the build stops a few hundred targets in with
  `error[E0463]: can't find crate for 'core'`, which names neither the leg nor the cause. The
  step reads the architecture off the triplet rather than off the runner - they disagree exactly
  when the leg is a cross build - and adds the matching target on every leg, because that is
  idempotent.

## 3. The matrix

Six legs: both architectures on each of the three platforms the manifest claims. A preset in
`test/CMakePresets.json` is named after the vcpkg triplet it selects, so it differs from the
triplet column below only where CI installs vcpkg's release-only variant of the same triplet.

| Leg | Runner | Preset | Triplet | Consumer | Blocking? |
|---|---|---|---|---|---|
| x64 Windows | `windows-2022` | `x64-windows-static` | `x64-windows-static-release` | Release | yes |
| arm64 Windows | `windows-11-arm` | `arm64-windows-static` | `arm64-windows-static-release` | Release | no — was failing inside the zlib overlay port; patch 0005 fixes that |
| x64 Linux | `ubuntu-latest` | `x64-linux` | `x64-linux-release` | Release | no — passes, still `experimental` |
| arm64 Linux | `ubuntu-24.04-arm` | `arm64-linux` | `arm64-linux-release` | Release | no — has never finished a build |
| arm64 macOS | `macos-latest` | `arm64-osx` | `arm64-osx-release` | Release | yes |
| x64 macOS | `macos-15` | `x64-osx` | `x64-osx-release` | Release | no — both causes fixed, the Rust target included |
| all six | weekly/manual | same | stock (dual) | **Debug** | off the push path |

`ci.yml` and `node-suite.yml` run the Release rows; `debug.yml` runs the last one, where no leg
is `experimental` because that workflow never runs on a push and its failures are exactly what
it exists to surface.

x64 macOS is a **cross build**: the runner is an arm64 image and both the port and the consumer
are asked for `x86_64` (the preset sets `CMAKE_OSX_ARCHITECTURES`, which is also what vcpkg
reads back to pick the triplet). The produced binaries run under Rosetta, hence the guard in
section 2.3. A native Intel runner would avoid that; none is used today.

Windows is pinned to `windows-2022` rather than `windows-latest`: the port pins the Visual
Studio 2022 toolset for gyp (`GYP_MSVS_VERSION`, `ports/node/portfile.cmake`) and needs its
clang-cl, which that image states.

Three legs have completed a build end to end: x64 Windows and arm64 macOS
([build.md](build.md), [node-suite.md](node-suite.md)), and - as of 2026-10-17 - x64 Linux,
which passed 17 of 17 cases in 1h29m once the release-only triplet stopped paying for a second
Node.js build ([issue #8](https://github.com/hz2769514387/vcpkg-port-node/issues/8)). The other
three legs are in the matrix rather than absent because the port claims to support them, and
leaving them red-but-non-blocking is how that claim stays honest instead of aspirational. Two of
the three now have a cause and a fix rather than a mystery: arm64 Windows died in this
repository's own zlib overlay port, because the fork's ARM SIMD branch only knows the POSIX
spellings of the architecture while CMake calls it `ARM64` on Windows - and on the way it also
needed `ARMV8_OS_WINDOWS` and no `-march`, none of which MSVC can take from the branch as written
(`ports/zlib/0005-arm64-windows-msvc.patch`) - and x64 macOS failed because the port's
host-architecture probe came back empty inside a portfile, which vcpkg runs with `cmake -P`, so
the build quietly took the native path and produced arm64 host tools that cannot link the x86_64
libraries vcpkg had installed. That probe is gone: the macOS presets state the target
architecture outright instead of comparing it against a host. Stating the target then met a
second, runner-side wall - `cargo --target x86_64-apple-darwin` wants the Rust standard library
for that architecture, which an arm64 image does not ship (section 2.3) - and that is provisioned
now too, so the leg is building. arm64 Linux is the one leg with neither cause nor fix yet,
because its cold build has never finished.

`experimental` is an input to `build-test.yml`, not `continue-on-error` on the caller, and the
legs are separate jobs rather than a matrix. Both keywords are accepted by the workflow parser
and then produce a run with **zero jobs** and a "workflow file issue" failure - a job that calls
a reusable workflow takes neither. If you add either back, that is what you will see.

The Windows presets name neither a generator nor an architecture, and both omissions are
deliberate. Naming a generator pins one Visual Studio version, while what the port needs is
2022 **or newer** - the requirement is written down in the README's *Known limits*, because a
too old Visual Studio fails inside the port's own build rather than at generator lookup - and
left alone CMake picks the newest Visual Studio installed. Leaving the architecture unstated
leaves the target machine type to the generator, whose default platform is the machine's own:
that is the machine type every Windows leg asks for, and stating it explicitly would make any
non-Visual-Studio generator a hard configure error.

Build presets in `test/CMakePresets.json` deliberately carry no `configuration`: on a
multi-config generator (Visual Studio) the configuration comes from `cmake --build --config`
and `ctest -C`, and on a single-config one from `CMAKE_BUILD_TYPE` at configure time. Stating
it in the preset as well would give two answers to the same question.

## 4. What the tests assert, and what they do not

- `smoke.*` — Node.js identity and provenance: the version the port claims, and whether every
  externalized dependency really came from vcpkg. See `test/smoke/externalization.mjs`.
- `node-suite.*` — Node.js's own suite through its own driver, with the **embedding
  executable** as the shell. That is the strongest available statement that libnode is a
  runtime and not just a library that links.

Neither replaces a symbol audit (two copies of one library in a single process is the failure
this repository exists to prevent) or a check that the delivered headers match the delivered
library. Those are tracked as work items, not skipped.

Skips live in `test/official_suite/node-suite-skips*.txt` with a mandatory reason per entry, and the
symbol-link ones are applied only after probing whether this machine can create symlinks —
a permission, not a platform property.

## 5. Caching

`VCPKG_BINARY_SOURCES` is `clear;files,<workspace>/vcpkg-archives,readwrite`, and an
`actions/cache` step persists that directory between runs. The key covers the runner, the
pinned vcpkg commit, the triplet and the contents of `ports/` plus the test manifest, because
any of those changing changes the ABI of what gets built. The triplet is part of the key
deliberately: different legs install different binaries and must not share an entry.

**A warm cache is why a leg can finish in minutes, and it is not a leg skipping its work.** The
restore keys deliberately fall back to an older entry of the same runner and triplet, so a run
whose `ports/` changed still starts from the previous archives, and vcpkg then reuses only the
ones whose ABI hash matches - a port change that changes what is built is therefore rebuilt, not
served stale. When `node` itself comes back from the archive the port is not compiled again, but
the leg still configures, still builds the consumer project and still runs ctest, which is what
makes the pass mean anything; the log says so explicitly
(`Restored 23 package(s) from <workspace>/vcpkg-archives in 5.6 s`). Two legs of the run for
`2e15776` finished in 35 s and 2m43s that way, against 1h29m for the same Linux leg on a cold
cache.

The obvious choice - the `x-gha` provider, which is what GitHub Actions caching used to mean
for vcpkg - was **removed from vcpkg**, and this repository's first CI run proved the failure
mode: `clear;x-gha,readwrite` prints a warning and then builds every dependency from source on
every run, because `clear` also removed the default files provider and the replacement never
loaded. The warning is easy to miss and costs an hour per platform, so the provider is stated
explicitly here. If a cache-backed source is ever wanted again, the supported options are a
NuGet feed (needs a token) or a files provider persisted by `actions/cache`, which is what this
is.

## 6. Reading a run's logs

Every leg uploads its logs unconditionally (`if: always()`), named
`logs-part-<triplet>-<config>`, and the `logs` job calls `logs.yml` to merge all of them into
one `ci-logs.tar.gz` (or `debug-logs` / `node-suite-logs`). One download per run.

The build step's output is tee'd, and the job summary carries the ctest pass/fail counts, the
list of failed tests and the first error, so the run page answers the obvious questions before
any log is opened. The port's own output is separate from the consumer's: vcpkg keeps a port's
stdout and stderr in `buildtrees/node/build-<config>-{out,err}.log`, and the manifest log embeds
only one of the two, which is why the collector copies both.

## 7. Release watch

`node-release-watch.yml` runs `tools/node_release_watch.py` once a day. The tool makes a
single request to `https://nodejs.org/dist/index.json`, compares the newest release of the
pinned line with `ports/node/vcpkg.json`, and makes sure exactly one open issue describes what
is available. Without a token it prints its finding and writes nothing, so it is safe to run
locally. A new *major* line is reported as a separate issue, because crossing one is a project
rather than a version bump.

## 8. What CI does not do

No tags, no releases, no publishing anywhere. The project is in its development period
(AGENTS.md, section 5), so `main` may be red and no interface is promised to consumers.
Releasing is the maintainer's decision.
