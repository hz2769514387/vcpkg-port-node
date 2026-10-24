# Changelog

One entry per release tag. Each entry is the same content as that tag's GitHub Release body, kept
here because a repository should read without a network. Versions are dates: see
[docs/versioning.md](docs/versioning.md) for why, and for what the three numbers mean.

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

**Upstream already moved on.** Node.js v26.12.1 and vcpkg 2026.10.16 were published while this was
being finished (issues #24, #25). Both are routine bumps on `main` in the maintenance period, each
with its own full matrix run.
