# Test-suite results

Results from running the official Node.js test-suite against the port-built
`node.exe`, on `x64-windows-static` with Node.js v26.11.1.

## Summary

| Metric | Value |
|---|---|
| Total tests | 4990 |
| Passed | 4960 |
| Failed | 30 |
| Pass rate | 99.4 % |
| Date | 2026-10-16 |
| Config | Release, `x64-windows-static` |

## How the test-suite is run

```
python <prefix>/share/node/test-suite/tools/test.py \
    --shell=<prefix>/tools/node/node.exe \
    --test-root=<prefix>/share/node/test-suite/test \
    parallel
```

The `test-suite` feature installs the test files and the `test.py` driver into
`<prefix>/share/node/test-suite/`.

## Failure categories

All 30 failures are environment-specific (Windows without symlink privilege)
or upstream test bugs on Windows. None are caused by the port.

### 1. Windows symlink EPERM (28 tests)

These tests call `fs.symlinkSync()` or equivalent, which fails with
`EPERM: operation not permitted, symlink ...` because the test runner does not
have the `SeCreateSymbolicLinkPrivilege` required on Windows to create
symlinks without elevation.

This is a standard Windows + Node.js CI limitation, not a port defect. The
official Node.js CI runs these tests with elevated privileges or with
Developer Mode enabled.

Failed tests:

- `test-child-process-exec-any-shells-windows.js`
- `test-fs-cp-async-copy-non-directory-symlink.mjs`
- `test-fs-cp-async-dereference-symlink.mjs`
- `test-fs-cp-async-destination-appears-late.mjs`
- `test-fs-cp-async-dest-symlink-points-to-src-error.mjs`
- `test-fs-cp-async-symlink-dest-points-to-src.mjs`
- `test-fs-cp-async-symlink-over-file.mjs`
- `test-fs-cp-async-verbatim-dir-symlinks-with-filter.mjs`
- `test-fs-cp-sync-copy-symlink-not-pointing-to-folder.mjs`
- `test-fs-cp-sync-copy-symlink-over-file-error.mjs`
- `test-fs-cp-sync-copy-symlinks-to-existing-symlinks.mjs`
- `test-fs-cp-sync-dereference-directory.mjs`
- `test-fs-cp-sync-dereference-file.mjs`
- `test-fs-cp-sync-dereference-nested-symlink.mjs`
- `test-fs-cp-sync-dereference.js`
- `test-fs-cp-sync-parent-symlink-dest-points-to-src-error.mjs`
- `test-fs-cp-sync-resolve-relative-symlinks-default.mjs`
- `test-fs-cp-sync-resolve-relative-symlinks-false.mjs`
- `test-fs-cp-sync-symlink-dest-points-to-src-error.mjs`
- `test-fs-cp-sync-verbatim-dir-symlinks-with-filter.mjs`
- `test-fs-cp-sync-verbatim-symlinks-true.mjs`
- `test-fs-lchown-negative-one.js`
- `test-fs-promises.js`
- `test-fs-rm.js`
- `test-fs-symlink-longpath.js`
- `test-fs-utimes.js`
- `test-fs-watch-recursive-symlink.js`
- `test-vfs-real-provider-symlinks.js`

### 2. CRLF in TypeScript compiler output (1 test)

`test-snapshot-typescript.js`: The TypeScript compiler (`tsc`) on Windows
outputs `\r\n` line endings, but the test expects `\n`. The assertion
`strictEqual` fails because `actual` has `\r\n` and `expected` has `\n`.

This is a known upstream Node.js test issue on Windows — `tsc` on Windows
produces CRLF. Not fixable by the port.

### 3. FORCE_COLOR / NO_COLOR warning (1 test)

`test-runner-reporters.js`: The test expects empty stderr but gets a
`Warning: The 'NO_COLOR' env is ignored due to the 'FORCE_COLOR' env being
set.` message. The test runner sets `FORCE_COLOR` which conflicts with
`NO_COLOR` in the environment.

This is an environment interaction, not a port defect.

## Fixes applied

### test-sqlite (fixed)

`test-sqlite.js` was failing because vcpkg's official `sqlite3` port does not
enable `SQLITE_ENABLE_FTS3_PARENTHESIS` (needed for FTS3 parenthesis query
syntax) or `SQLITE_ENABLE_RBU` (needed for the Resumable Bulk Update
extension). Node.js's own `deps/sqlite3/sqlite3.gyp` enables both.

Fix: a `ports/sqlite3` overlay port that adds these two compile flags to the
`fts3` and `session` features respectively, and adds the corresponding
`#cmakedefine` entries to `sqlite3-vcpkg-config.h.in` so they are visible to
`sqlite3.c` at compile time.

After the fix, `test-sqlite.js` passes all 21 sub-tests.