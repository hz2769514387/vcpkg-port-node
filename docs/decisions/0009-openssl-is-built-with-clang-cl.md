# 9. OpenSSL is compiled with clang-cl, the compiler Node.js requires

- Status: Accepted
- Date: 2026-10-19
- Supersedes: the no-asm half of [0008](0008-icu-comes-from-vcpkg.md)'s reasoning is unaffected;
  this ADR replaces the 2026-10-19 experiment recorded in `ports/openssl/` that pinned
  `no-asm` instead.

## Context

Node.js requires clang-cl on Windows: `vcbuild.bat` forces it for every version >= 24
("ClangCL is required because the Node.js version being compiled is >= 24"), and V8 does not
compile with `cl.exe` at all. [ADR 0007](0007-toolchain-configuration-and-linkage-policy.md)
therefore pins the port and its consumer to clang-cl.

vcpkg builds its own ports with cl.exe. That left one library inside every Node.js process
compiled by a different compiler than the rest: OpenSSL, which this port externalizes
(`--shared-openssl`).

What that cost, measured on the arm64 Windows leg:

- 250 of the official suite's cases died with `--- CRASHED ---` and no other output. The driver
  discards the exit code on Windows, so for three rounds they had no signature at all.
- The official Node.js binary, run through the same suite on the same runner, crashed in none
  of them ([run 39201696549](https://github.com/hz2769514387/vcpkg-port-node/actions/runs/39201696549)),
  so this was the port's own build, not the platform and not upstream.
- Two hypotheses were eliminated first: OpenSSL's version (the official binary ships 3.5.x,
  this port 3.6.3) and OpenSSL's aarch64 assembly. Building OpenSSL with `no-asm` - which is
  what Node.js does for its own vendored OpenSSL on Windows arm64 - changed nothing: the crash
  count stayed at 250 and the set of 254 failing tests was byte-identical to the previous run.

## Decision

**The `openssl` overlay exists to build OpenSSL's C code with clang-cl.** It points
`VCPKG_DETECTED_CMAKE_C_COMPILER` at the clang-cl that Visual Studio ships for the machine's
own architecture, and changes nothing else: same version (3.6.3, never downgraded to match
upstream's 3.5.x), same options, same assembly settings, same install layout.

Everything else stays put:

- The assembler is left as the baseline ships it (already clang), so the result is attributable
  to the C compiler alone.
- No change to ICU, which remains on cl.exe for the reason
  [ADR 0008](0008-icu-comes-from-vcpkg.md) records (vcpkg's `icu` port is autotools and cannot
  be driven by clang-cl). ICU is a C API and the ABI surface that matters - machine type, CRT,
  exceptions - matches; OpenSSL turned out not to be such a case.

## Consequences

- The arm64 Windows leg passes: run 39273404007 reports **all six legs green**, the suite at
  **100% (29 and 20 tests in the two consumer configurations)**, **0 crashes** and no failing
  cases. Issue #22 is closed by that measurement.
- The port now carries a second overlay whose reason is a compiler rather than a version:
  `openssl` joins the seventeen that exist for other reasons, and is disclosed in
  `docs/overlay-replacements.md`.
- The compiler question is answered for OpenSSL and left open for ICU. If a future defect looks
  like this one - silent, confined to one library's code, absent from the official binary - the
  first question is which compiler built that library.

## Revisit when

vcpkg's openssl port builds with the same compiler as the consumer by default, or the port
stops externalizing OpenSSL.
