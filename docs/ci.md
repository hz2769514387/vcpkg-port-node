# CI reference

What runs, where, and what each run actually proves. Every workflow lives in
`.github/workflows/`; anything about *why* the gates are shaped this way is in the ADRs, not
here ([0002](decisions/0002-node-version-policy.md), [0003](decisions/0003-vcpkg-baseline-policy.md),
[0004](decisions/0004-continuous-integration.md),
[0005](decisions/0005-vcpkg-pin-without-a-manifest-baseline.md),
[0010](decisions/0010-build-cells-run-when-a-change-can-affect-the-build.md)).

## 1. The gates

| Workflow | Trigger | Cost | Decides |
|---|---|---|---|
| `lint.yml` | push to `main`, pull request, manual | seconds | the repository still obeys its own rules: version files match the ports, tracked files are English/LF/UTF-8, referenced patches exist |
| `ci.yml` | a build-affecting push or pull request, manual | tens of minutes to a few hours per leg | the port **builds and can be consumed**, as a Release and as a RelWithDebInfo consumer, and **what was built is still Node.js** - Node.js's own suite runs on the Release consumer of every leg |
| `debug.yml` | a build-affecting push or pull request, weekly, manual | about twice `ci.yml` per leg | the same for the **Debug** configuration, which needs a Debug library and therefore its own install |
| `matrix.yml` | a build-affecting push or pull request, weekly, manual | about twice `ci.yml` per leg | the rest of the matrix: the **dynamic CRT** on Windows and a **shared libnode** on every platform |
| `node-release-watch.yml` | daily (06:23 UTC), manual | seconds | whether upstream has published a newer Node.js release (ADR 0002) |
| `vcpkg-release-watch.yml` | daily (06:53 UTC), manual | seconds | whether upstream has published a newer vcpkg release (docs/versioning.md) |

### When the build cells run

The three build workflows trigger only when a path that can change what is built has changed:
`ports/**`, `test/**`, `tools/**`, `.github/**`, `versions.json`, `versions/**`. A change to
documentation alone - `docs/**`, the repository's own markdown - runs **Lint only**, which is the tier
that can fail on it (`check_repo.py`, `version_tree.py --check`, `check_secrets.py`,
`check_workflows.py`, `overlay_table.py --check`).

That is [ADR 0010](decisions/0010-build-cells-run-when-a-change-can-affect-the-build.md), and it
changes what "green" means for such a commit: Lint green, and no matrix result *because there was no
matrix question*. Scheduled and manual runs are not filtered - their purpose is to notice drift, not
to judge a change.

The failure mode to watch is the list itself: a file a build reads that is not on it stops being
built, silently. The list is short, it lives in three files that are themselves under `.github/**`
(so editing it reruns the cells), and anything new at the repository root that a build consumes has
to be added in the same commit.

Every dimension this repository verifies is exercised on push - and the one it does not verify is
named rather than implied (see the Debug subsection below). What is *not* true is that every
dimension is verified inside one job: `debug.yml` and `matrix.yml` exist because a job that installed the port for
three configurations and ran the suite three times would exceed GitHub's six-hour job limit,
while three workflows run in parallel and each stays inside it (ADR 0007).

The limit applies **per job**, which is the other half of that argument. A leg that fits one job
is one job; the one leg that does not fit - Linux x64 Debug - runs as two, with
`split-install: true`:

| | `split-install: false` (default) | `split-install: true` |
|---|---|---|
| jobs | one | `install`, then `build` (`needs: install`) |
| what crosses between them | - | the installed tree, as a **tar** (`port-install-<triplet>`, 1-day retention) |
| used by | every leg except Linux x64 Debug | Linux x64 Debug |

Four things were measured on 2026-10-21/22 and each changed the shape of this:

- **A cold dual install is 4.5 hours** on a four-core runner (4.1 of them node). That fits the
  ceiling with about an hour to spare, which is why this leg is split and the others are not.
- **A zip artifact loses file modes.** Run 39500147659's consumer job refused to configure with
  "test suite fixture lost its executable bit" on `.bin/ada`. The tree is a **tar** inside the
  artifact now (`tar -cf` / `tar -xf`), which carries the modes.
- **Three copies of one tree do not fit on one disk.** Run 39729687647 lost the install job at
  "Upload the installed tree" with no artifact *and* no log artifact - a dead runner. vcpkg's
  build tree, the installed tree and its tar were on one 14 GB volume. The job now drops
  `vcpkg/buildtrees` and `vcpkg/packages` before packing and the installed tree once the tar
  holds it, and prints `df -h` either side.
- **The Actions cache cannot be a dependency.** The cache is 10 GB per repository; ten legs'
  archives evict each other, so a prepare job that fills it works on some rounds (an install in
  12 minutes instead of 4.5 hours) and not on others (run 39758350009 spent its full six hours
  rebuilding). Two cheaper shapes were tried and dropped: that cache-warming job, and a
  Release-only install, which is not reachable at all - neither a step-level `env:` nor an action
  input reaches vcpkg in manifest mode (run 39534901582 printed `VCPKG_BUILD_TYPE=release` from
  the shell and `-- node port: VCPKG_BUILD_TYPE unset` from the port).

### Debug is four cells

`debug.yml` runs Windows x64, Windows arm64, macOS arm64 and macOS x64. All four build the same dual
install in one job, in two to three hours: clang-cl and Apple's clang do the work that a four-core
Linux runner needs more than six hours for.

**Neither Linux cell has a Debug leg.** The dual install is 5h36m of vcpkg work on four cores with
every dependency cached, so the x64 leg landed on either side of the six-hour ceiling from one run to
the next, and arm64 never finished at all. Both are gone; the measurements are in the section below
the cell table. That is a runner limit, not a port limit - a machine with more cores builds the same
configuration - and it is the one dimension this repository's CI does not verify on Linux.

The build-and-test workflows all call `.github/workflows/build-test.yml`, which is the only
place the build steps exist. They differ in which `preset` and `triplet` they pass, in which
`consumer-configs` they build the consumer as, in which of those run Node.js's own suite
(`suite-configs`), and in whether a leg is blocking. Each of them also ends with a job that
calls `.github/workflows/logs.yml`, which merges every leg's logs into **one** archive per run
(section 6) - reading a run is one download, not one per platform.

`node-suite.yml` is gone: it ran Node.js's suite once a week on the same six cells that
`ci.yml` now builds on every push, with the suite included. Keeping both would have meant
maintaining two descriptions of the same thing.

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

### 2.1 Which install, and which consumer configurations

A leg installs the port once and then builds the consumer once per configuration in
`consumer-configs` - the install is the expensive part and the loop is not. On a multi-config
generator (Visual Studio) every configuration already exists in one build tree; on a
single-config one (Ninja, Makefiles) `CMAKE_BUILD_TYPE` is fixed at configure time, so the loop
reconfigures before it builds, and vcpkg - already satisfied - costs nothing the second time.

`VCPKG_BUILD_TYPE` can only be set in a triplet, and leaving it unset makes the port build
Release **and** Debug - two Node.js builds per leg. That is what pushed the Linux leg past the
five-hour job limit. `ci.yml` therefore names vcpkg's own **community** `*-release` triplets -
`x64-windows-static-release`, `arm64-windows-static-release`, `x64-linux-release`,
`arm64-linux-release`, `arm64-osx-release`, `x64-osx-release` - which are the standard settings
plus `VCPKG_BUILD_TYPE release`. vcpkg ships them, so this repository carries no triplet file,
and a consumer can name them too without copying anything.

`debug.yml` installs the *stock* (dual) triplet instead, because Debug is a property of the
install rather than of the consumer: on Windows a Debug consumer is the debug CRT and cannot
link a Release library. Debug-only is not an option either - a debug-only triplet moves every
install into `${prefix}/debug/...` and seven ports in this port's dependency closure (brotli,
c-ares, libuv, ngtcp2, openssl, zstd, and this repository's own zlib overlay) run post-install
fixups against the non-debug layout and fail there. The measurements are in issue #11.

Node.js's own suite runs on the configurations named by `suite-configs` and on no others: it
costs the better part of an hour, and running it against RelWithDebInfo would re-run the suite
against the same release library with symbols attached. Every other case - identity,
embedding, symbol, zlib - runs on every configuration a leg builds.

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
- **Retrying only download failures.** vcpkg has no retry of its own for a source tarball or for
  its own git fetch, and one timeout from an upstream mirror costs the whole leg. The configure
  step retries, but only when the failure is a download problem, decided by two signature lists:
  a *positive* download list (`Download failed`, `Couldn't resolve host name`, `RPC failed`,
  `HTTP 5xx`, `curl: (n)`, ...) and a *positive* compiler-and-linker list (`ninja: build
  stopped`, `error C<number>`, `undefined reference`, `LNK<number>`, ...).
  Matching on "download" is not enough on its own, because the log quotes absolute paths such as
  `.../vcpkg/downloads/<archive>`, so a plain build failure matches it too - and a bare
  `Timeout` is just as bad, since a configure log on this port legitimately contains
  `absl_kernel_timeout_internal.pc`. The download list therefore holds download-*phase* strings
  only.
  The list that has to be positive is the second one. Every vcpkg failure - download included -
  ends with `CMake Error at .../vcpkg_execute_required_process.cmake` and `building <port>
  failed with: BUILD_FAILED`, so the first version of this step, which vetoed on exactly those
  two strings, vetoed every download failure as well and could never retry anything. It was
  measured twice before it was corrected: a runner whose DNS was down (`curl 6`, "Couldn't
  resolve host name") on the macos-x64 leg, and an `HTTP 503` from `chromium.googlesource.com`
  in the zlib overlay's git fetch on the macos-x64 Debug leg. Both died on their first attempt
  with "not a download problem".
- **No empty array expansion under `set -u`.** macOS still ships bash 3.2 as `/bin/bash`, and
  there expanding an *empty* array under `set -u` aborts with `<name>[@]: unbound variable`
  (legal from bash 4.4). `suite-configs` is legitimately empty on the Debug and matrix legs, so
  the step tests membership against the comma-separated string instead of looping over an
  array - one form that behaves the same on every bash. The first version looped over the array
  and failed every such leg on macOS and only on macOS, which is a hard failure to attribute
  because the same leg passes in `ci.yml`, where the suite runs.
- **The Rust standard library for the target architecture.** The port builds Node.js's Rust
  crates with `cargo --target <triple>`, and a rustup toolchain ships the standard library for
  the architecture it was installed for - which on an x64-osx leg is not the one the triplet
  asks for. Without it the build stops a few hundred targets in with
  `error[E0463]: can't find crate for 'core'`, which names neither the leg nor the cause. The
  step reads the architecture off the triplet rather than off the runner - they disagree exactly
  when the leg is a cross build - and adds the matching target on every leg, because that is
  idempotent.

## 3. The matrix

A preset in `test/CMakePresets.json` is named after the vcpkg triplet it selects, so it differs
from the triplet column below only where CI installs vcpkg's release-only variant of the same
triplet. Every `ci.yml` and `matrix.yml` leg installs such a variant, because a dual triplet
builds Node.js twice and that is what used to put single legs past the six-hour job limit.
`debug.yml` is the exception, and the reason it is a workflow of its own: it installs the stock
dual triplet once, which builds Release *and* Debug, and then builds a Debug consumer against it.

A consumer configuration follows from that: Release and RelWithDebInfo work against any install,
Debug needs one that also holds debug libraries. No `matrix.yml` leg builds a Debug consumer,
and this repository carries no triplets of its own, so a Debug consumer on a shared or `/MD`
libnode is not verified yet - see issue #11 rather than assuming it from a passing leg.

Every cell below is a promise a consumer can hold this repository to, and each one is a leg.

| Workflow | Leg | Runner | Preset | Triplet | Consumer | Node.js suite | Blocking? |
|---|---|---|---|---|---|---|---|
| `ci.yml` | x64 Windows | `windows-2022` | `x64-windows-static` | `x64-windows-static-release` | Release, RelWithDebInfo | Release | yes |
| `ci.yml` | arm64 Windows | `windows-11-arm` | `arm64-windows-static` | `arm64-windows-static-release` | Release, RelWithDebInfo | Release | yes |
| `ci.yml` | x64 Linux | `ubuntu-latest` | `x64-linux` | `x64-linux-release` | Release, RelWithDebInfo | Release | yes |
| `ci.yml` | arm64 Linux | `ubuntu-24.04-arm` | `arm64-linux` | `arm64-linux-release` | Release, RelWithDebInfo | Release | yes |
| `ci.yml` | arm64 macOS | `macos-latest` | `arm64-osx` | `arm64-osx-release` | Release, RelWithDebInfo | Release | yes |
| `ci.yml` | x64 macOS | `macos-15` | `x64-osx` | `x64-osx-release` | Release, RelWithDebInfo | Release | yes |
| `debug.yml` | four: the six above minus **both** Linux legs ([#26](https://github.com/hz2769514387/vcpkg-port-node/issues/26), [#46](https://github.com/hz2769514387/vcpkg-port-node/issues/46)) | as above | as above | stock (dual) | **Debug** | — (off) | yes |
| `matrix.yml` | x64 Windows, `/MD` | `windows-2022` | `x64-windows-static-md` | `x64-windows-static-md-release` | Release, RelWithDebInfo | Release | no — new cell |
| `matrix.yml` | arm64 Windows, `/MD` | `windows-11-arm` | `arm64-windows-static-md` | `arm64-windows-static-md-release` | Release, RelWithDebInfo | Release | no — new cell |
| `matrix.yml` | x64 Windows, shared | `windows-2022` | `x64-windows` | `x64-windows-release` | Release, RelWithDebInfo | Release | no — new cell |
| `matrix.yml` | arm64 Windows, shared | `windows-11-arm` | `arm64-windows` | `arm64-windows-release` | Release, RelWithDebInfo | Release | no — new cell |
| `matrix.yml` | x64 Linux, shared | `ubuntu-latest` | `x64-linux-dynamic` | `x64-linux-dynamic-release` | Release, RelWithDebInfo | Release | no — new cell |
| `matrix.yml` | arm64 Linux, shared | `ubuntu-24.04-arm` | `arm64-linux-dynamic` | `arm64-linux-dynamic-release` | Release, RelWithDebInfo | Release | no — new cell |
| `matrix.yml` | arm64 macOS, shared | `macos-latest` | `arm64-osx-dynamic` | `arm64-osx-dynamic-release` | Release, RelWithDebInfo | Release | no — new cell |
| `matrix.yml` | x64 macOS, shared | `macos-15` | `x64-osx-dynamic` | `x64-osx-dynamic-release` | Release, RelWithDebInfo | Release | no — new cell |

### Why no Linux Debug cell

A Debug consumer needs a Debug library, so the port has to be installed for both configurations -
Node.js built twice - and on a four-core runner that install is **5h36m of pure vcpkg work with every
dependency cached**. GitHub's ceiling is six hours *per job*, which is why the leg was once split into
an install job and a build job; the split does not help, because the install is the half that takes
the time.

Three consecutive runs of the x64 leg, with the measurements that decided it:

| `linux / install` | outcome |
|---|---|
| 6h00m | cancelled at the ceiling |
| 5h47m | passed - by thirteen minutes |
| 6h05m | cancelled at the ceiling |

arm64 never finished in any of three attempts. A leg that decides by runner load is worse than a gap
that is written down: it makes every pull request's signal depend on the queue. So both Linux Debug
legs are gone, and **Debug is verified on four cells** - both Windows architectures and both macOS
ones. Bringing it back needs a runner with more cores, not a cleverer workflow; the split shape is in
`git log -- .github/workflows/build-test.yml` if that day comes.

Every cell in that table has completed a build end to end, and the eight `matrix.yml` cells are
green as well: the port's claim to support them is verified rather than aspirational.

**Four of them block a merge, four do not** (#35). The blocking four are the shared-library cells -
`windows-shared`, `windows-shared-arm64`, `linux-shared`, `linux-shared-arm64` - because a shared
libnode changes how the consumer finds the library at run time and what the exported config links,
and no other leg carries that claim. They put the slowest cell in front of every pull request: 155
minutes for `linux-shared-arm64` on the last all-green run, the rest 72-131.

The non-blocking four are `windows-md`, `windows-md-arm64`, `macos-shared` and `macos-shared-x64`.
That is a cost decision, not a claim that they pass more often: `/MD` differs from the static-CRT
legs only in the CRT, which MSVC refuses to mix at link time anyway (`LNK2038`), and the macOS shared
cells repeat the shared claim on the platform whose rpath this repository tests through `ci.yml`.
Either becomes blocking by deleting one line in `matrix.yml` and saying why there.

What is genuinely not verified is Node.js's own suite on a few cells, and the known limits of the
delivered library; section 4 and the README's *Known limits* are the record for those.

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
  externalized dependency really came from vcpkg. See `test/cases/externalization/externalization.mjs`.
- `node-suite.*` — Node.js's own suite through its own driver, with the **embedding
  executable** as the shell. That is the strongest available statement that libnode is a
  runtime and not just a library that links.

Neither replaces a symbol audit (two copies of one library in a single process is the failure
this repository exists to prevent) or a check that the delivered headers match the delivered
library. Those are tracked as work items, not skipped.

Skips live in `test/cases/suite/node-suite-skips*.txt` with a mandatory reason per entry, and the
symbol-link ones are applied only after probing whether this machine can create symlinks —
a permission, not a platform property.

### 4.1 The suite's working directory is load-bearing

The driver hands the shell `--test-reporter=./test/common/test-error-reporter.js`, a **relative**
path, so it resolves against whatever directory the process was started in. `add_test` defaults
that to the *binary* directory, which is where `cases/suite/` is generated and where no `test/`
exists. Every case that uses the reporter then dies with

```
ERR_MODULE_NOT_FOUND ... /cases/suite/test/common/test-error-reporter.js
```

while the cases that do not use it pass, because the suite's own files reach the driver through
`--test-root` either way. A partially red suite is the misleading version of this failure: it
looks like two dozen unrelated Node.js defects rather than one wrong directory. The tests set
`WORKING_DIRECTORY` to the installed suite root (`test/cases/suite/CMakeLists.txt`).

### 4.2 Anything that depends on Windows ACLs is suspect before it is ours

Four cases drive `icacls` to deny access and then assert `EPERM`:
`test-fs-mkdir-recursive-eaccess`, `test-fs-rm`, `test-fs-rmSync-special-char-additional-error`
and `test-module-readonly`. They pass on an ordinary Windows machine and fail on a
GitHub-hosted Windows runner, which runs the job as an account in the Administrators group - a
deny ACE is not the same obstacle for an elevated process, and `icacls` reports a non-ASCII path
as not found. Two consequences for reading a run:

- a failure in this group is a candidate for the skip list, not automatically a defect here;
- before one is written off, the same case has to be run on the same runner with the **official**
  Node.js binary - official passes and ours fails is the only thing that makes it ours. That
  cross-check is not wired into CI yet.

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

`vcpkg-release-watch.yml` is the same idea for the other pin. `tools/vcpkg_release_watch.py`
asks GitHub's API for the latest `microsoft/vcpkg` release, compares its date tag with
`vcpkg.release` in `versions.json`, and - only when something newer exists - makes one more
request for that release's commit, because that is the `vcpkg-commit` value the upgrade has to
put in the workflows. The issue body lists the three places the bump moves together. The tool
never edits a pin: ADR 0003 makes the upgrade a reviewed change.

Both watchers share `tools/release_watch_common.py`, which is the part that talks to this
repository (`gh` only, `origin` only, nothing without a token), so the safety rules cannot
drift apart between them. `lint.yml` runs both with `--dry-run` on every push, which is what
catches an upstream API change before the daily run does.

## 8. The official-binary baseline

`official-binary-baseline.yml` answers one question: **is this failure ours, or the machine's?** It
downloads the official Node.js binary for the pinned version and the suite from the same release's
source tarball, then runs the suites with `tools/test.py --shell=<official binary>` — the same
driver, the same cases, a different binary. Four legs: both Windows architectures and both macOS
ones, since those are the cells where this repository has questions and upstream's CI has no answer.

It is a **measurement, not a gate**: `workflow_dispatch` only, one `suites` input (space-separated
directory names, default `parallel`), about an hour per leg. The skip lists ask for exactly this
comparison — *official passes and ours fails means look here, not at Node.js* — and two entries in
`node-suite-skips.txt` were decided by it: the `process.execve` family on x64 macOS (issue #33) and
the Windows ACL cases (issue #21).

Nothing runs it automatically, and nothing should: a baseline from a runner whose load differs from
the leg being compared proves nothing.

## 9. What CI does not do

No tags, no releases, no publishing anywhere. Releasing is the maintainer's decision, and the
checklist that has to be true first is in `docs/versioning.md` §4 — CI verifies, nothing tags.

One workflow exists only for that checklist: `benchmark.yml`, dispatched by hand, which compares
the built node against the official binary of the same version (startup plus a fixed four-case
workload under `tools/benchmark_workload.js`). It is not on push on purpose — a benchmark needs a
quiet machine, and a number that moves with the runner's neighbours is worse than no number.
