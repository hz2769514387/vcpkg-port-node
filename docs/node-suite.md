# Node.js test suite — how it is run, and how to read the result

Reference for the one test that decides whether what this repository builds is still
Node.js. It is deliberately free of result numbers: a pass rate in a document goes stale the
next time anything is rebuilt, and a stale number in `docs/` is worse than no number because
it looks authoritative. Current results live where they are produced — the
[`node-suite` CI workflow](../.github/workflows/node-suite.yml) and its run history — and the
discussion of a specific run belongs in the issue that run was filed against.

What belongs here is what does not change: how to run the suite, how to read what it says,
and the discipline for deciding that something is allowed to fail.

## 1. How it runs

The suite is Node.js's own, driven by Node.js's own driver:

```
python <prefix>/share/node/test-suite/tools/test.py \
    --shell=<the executable under test> \
    --test-root=<prefix>/share/node/test-suite/test \
    --time --flaky-tests=dontcare <suite> [<suite> ...]
```

The executable under test is the **embedding executable the consumer test project links**
(`test/cases/embed`), not the port's own `node.exe`. That is the stronger claim: a runtime a
consumer links from `libnode` runs the official suite.

`test/cases/suite/CMakeLists.txt` registers one ctest case per suite, and `ci.yml` /
`node-suite.yml` choose which cases run by label: `-R node-suite` for the full run, `-LE
node-suite` for everything else.

Why the official driver and not `node --test`: every test directory carries a `*.status` file
in which upstream records its own SKIP and FLAKY verdicts, and only `tools/test.py` reads
them. Ignoring those files turns dozens of upstream-tagged cases into failures, and that
noise is what hides the one failure that is actually ours.

## 2. How to read a result

| Outcome | Meaning |
|---|---|
| pass | the case ran and agreed |
| skipped | upstream marked it SKIP or FLAKY in `*.status`, or it is on this repository's skip list with a written reason |
| fail | the case ran and disagreed. Start from the assumption that it is ours |

`--flaky-tests=dontcare` means cases upstream marks flaky still run, and a failure of theirs
does not by itself turn this repository red. It does not mean their failures are ignored: a
pattern in them is a signal about the machine, not about Node.js.

## 3. Before anything is allowed to fail

The order matters, and it is the difference between a skip list that documents the
environment and one that hides defects:

1. **Is it upstream's decision already?** `*.status` files carry SKIP and FLAKY. Listing those
   again duplicates upstream's judgement and freezes it.
2. **Is the file missing because we installed too little?** Install the file. A missing
   fixture is an installation defect, not an environment fact.
3. **Did it crash in native code?** Then suspect this build. The check that settles it: run
   the same case against the **official** Node.js binary for the same version. Official
   passes and ours fails means the defect is here.
4. **Only then is it the environment**, and it goes in `test/cases/suite/node-suite-skips.txt` with
   one sentence saying why — which the CMake code enforces by refusing to configure an entry
   without a reason.

A skip whose reason cannot be written is not a skip. It is an open question, and it belongs in
an issue.

## 4. Categories that are environment-dependent rather than broken

These are the shapes of failure that reproduce on a developer machine and not on CI, or the
other way round. They are described by mechanism, not by test name, because names change
between Node.js versions:

- **Symlink privilege.** Creating a file symlink on Windows requires
  `SeCreateSymbolicLinkPrivilege`, which a normal unprivileged process does not have. It is a
  property of the account, not of the platform: developers with Developer Mode enabled and
  most CI images can create them, a plain local shell cannot. The skip list therefore does not
  guess from the platform name — `cases/suite/CMakeLists.txt` probes whether this machine can create
  a symlink and only then applies `test/cases/suite/node-suite-skips-symlink.txt`.
- **Line endings in generated output.** A TypeScript compiler run on Windows emits CRLF where
  a fixture expects LF. Nothing the port can fix; it recurs whenever a tool's output is
  compared byte for byte.
- **Environment variables the runner itself sets.** A test asserting empty stderr can fail
  because the environment carries both `NO_COLOR` and `FORCE_COLOR`, which Node.js warns
  about. Re-check against the official binary before trusting this one.

Every entry in the skip lists is re-examined when the pinned Node.js version changes
(ADR 0002), because a new patch release can turn an environment failure into a fixed one, or
into a new failure with a different cause.

## 5. What a green run does and does not prove

A green run proves the delivered artifacts run Node.js's own tests. It does not prove that a
consumer process contains exactly one copy of each externalized library — the linker resolves
duplicate static definitions silently, so that needs a symbol audit instead (tracked
separately). It also does not prove anything about platforms whose leg has never completed a
build.

One case is skipped by linkage rather than by platform, and the configuration decides it
rather than a skip list: `abort/test-abort-backtrace` requires a native stack frame to name
the executable, which is true when node's code is linked *into* the executable (a static
libnode) and cannot be true when it lives in `libnode.<module>.dylib` / `.so` — the trace is
complete and symbolised, it simply names the library. `node_LIBRARY_LINKAGE`, exported by the
port's CMake config, is what `test/cases/suite` reads to decide.
