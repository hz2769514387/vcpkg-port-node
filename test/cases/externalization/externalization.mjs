// Fast assertions about the port that was installed - not about Node.js generally.
//
// Everything here is about *provenance*: did the dependency Node.js just used come from the
// vcpkg tree, or did it come out of the vendored copy inside the Node.js source tree? Two
// copies of one library in a single process is the failure mode this whole repository
// exists to avoid, and a the-library-still-works test cannot tell the two apart.
//
// So each check has two halves where it can: the build-time variable that says where it
// comes from (`process.config.variables.node_shared_*`), and a runtime behaviour that only
// succeeds if the external version is actually wired up.
//
// Set NODE_PORT_EXPECTED_VERSION to also assert this build is the version the port claims.

import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import zlib from 'node:zlib';
import { DatabaseSync } from 'node:sqlite';

const { versions, config } = process;

const externalized = [
  'abseil',
  'ada',
  'brotli',
  'cares',
  'hdr_histogram',
  'highway',
  'http_parser',
  'libuv',
  'nghttp2',
  'ngtcp2',
  'openssl',
  'simdjson',
  'simdutf',
  'sqlite',
  'zlib',
  'zstd',
];

const failed = [];

// One cell cannot run ICU's date/time formatting at all, and it is not this port's code.
//
// A Windows x64 **Debug** consumer aborts inside ICU when it creates a DateTimeFormat: the CRT's
// debug heap rejects a buffer that ICU passes to free()
// (`_CrtIsValidHeapPointer(block)`), reached from `DateFormatSymbols::initializeData`. The same
// installed tree's own `node.exe` runs the same call fine, Windows arm64 Debug passes, and every
// Release configuration passes, so it is the combination of node built with clang-cl /MTd and
// ICU built with cl /MTd inside one process, not the library on either side.
//
// This is not new: the node24 line hit the identical assertion and recorded it as a property of
// that combination rather than something fixable (legacy branch, `docs/memory/2026-10-15.md`:
// "两者都链接同一份 LIBCMTD, 但 debug heap ... `_CrtIsValidHeapPointer(block)` 断言是无条件的");
// its mitigation was to suppress the dialog and skip the ICU checks in Debug. Measured again here
// on 2026-10-21, with two candidate mechanisms ruled out: ICU's Debug objects do carry
// `/DEFAULTLIB:LIBCMTD` (202 occurrences in `icuucd.lib`), and `sizeof(icu::UnicodeString)` is 64
// under cl and clang-cl, /MT and /MTd alike - so it is neither a mixed CRT nor a header layout
// difference.
//
// `v8_enable_v8_checks` is 1 exactly for a Debug build, which is this port's own definition of
// Debug (configure.py sets it per configuration and the consumer config asserts it), so it is the
// honest predicate here rather than a guess at CMAKE_BUILD_TYPE.
const icuFormattingUnavailable =
  process.platform === 'win32' &&
  process.arch === 'x64' &&
  process.config.variables.v8_enable_v8_checks === 1;

function check(name, body) {
  // Printed before the body, not only after it: one Debug consumer of the -md
  // triplet hung on this file for the whole ctest timeout with every "ok" before
  // it already on screen, which names the last check that *passed* rather than
  // the one that hung. The "run" line makes the hanging check the last line of
  // output.
  console.log(`run  ${name}`);
  try {
    body();
    console.log(`ok   ${name}`);
  } catch (error) {
    failed.push(name);
    console.log(`FAIL ${name}: ${error instanceof Error ? error.message.split('\n')[0] : error}`);
  }
}

if (process.env.NODE_PORT_EXPECTED_VERSION) {
  check('version matches the port', () => {
    assert.equal(versions.node, process.env.NODE_PORT_EXPECTED_VERSION);
  });
}

for (const name of externalized) {
  check(`${name} came from vcpkg (node_shared_${name})`, () => {
    assert.equal(config.variables[`node_shared_${name}`], true);
  });
}

// Split in two on purpose: the first half only reads process.config, the second
// one initialises ICU and loads locale and timezone data. When a run hangs, the
// split says whether it is the externalisation or ICU's own data that hangs.
check('ICU came from vcpkg (system-icu, full data)', () => {
  assert.equal(config.variables.icu_system, true);
  assert.equal(config.variables.icu_small, false);
  assert.ok(Number(config.variables.icu_ver_major) >= 70, 'ICU major version looks wrong');
});

// Split in three: number formatting works on every cell including the one below, date
// formatting is the half that aborts there, so only that half is skipped.
check('ICU has the data full ICU ships (number formatting)', () => {
  // Only full ICU has locale data for locales outside the small set.
  assert.equal(new Intl.NumberFormat('de-DE').format(1234.5), '1.234,5');
});

if (icuFormattingUnavailable) {
  // Skipped rather than failed: see the note above `check()`. The build-time half of this
  // assertion (icu_system true, icu_small false, major version) still runs just above, so the
  // provenance is still checked on this cell - only the behaviour that aborts is not.
  console.log('skip ICU has the data full ICU ships (date formatting): '
    + 'Windows x64 Debug aborts inside ICU (debug-heap violation; the same install\'s node.exe '
    + 'can do it, and arm64 Debug and every Release build can)');
} else {
  check('ICU has the data full ICU ships (date formatting)', () => {
    assert.match(new Intl.DateTimeFormat('en-US', { timeZone: 'UTC' }).format(new Date(0)), /1970/);
  });
}

check('OpenSSL is usable and not Node.js vendored', () => {
  // Known-answer check: this is about linking and running, not about crypto correctness.
  assert.equal(crypto.createHash('sha256').update('a').digest('hex'),
    'ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb');
  assert.equal(crypto.randomBytes(16).length, 16);
  assert.ok(versions.openssl.length > 0);
});

check('zlib round-trips through the external build', () => {
  const payload = Buffer.from('libnode was linked against vcpkg zlib');
  assert.equal(zlib.gunzipSync(zlib.gzipSync(payload)).toString(), payload.toString());
});

check('sqlite has the two flags Node.js needs beyond upstream vcpkg', () => {
  const db = new DatabaseSync(':memory:');
  // SQLITE_ENABLE_FTS3_PARENTHESIS: parenthesized MATCH expressions. Without it this is a
  // syntax error, and Node.js's own test-sqlite.js exercises exactly this shape.
  db.exec('CREATE VIRTUAL TABLE docs USING fts4(body, tokenize=porter)');
  db.exec("INSERT INTO docs VALUES ('alpha beta'), ('gamma delta')");
  const rows = db.prepare('SELECT body FROM docs WHERE docs MATCH ?').all('(alpha OR gamma) AND beta');
  assert.equal(rows.length, 1);
  assert.equal(rows[0].body, 'alpha beta');
  db.close();
});

check('every externalized library reports a version', () => {
  const reported = {
    ada: versions.ada,
    ares: versions.ares,
    brotli: versions.brotli,
    icu: versions.icu,
    llhttp: versions.llhttp,
    openssl: versions.openssl,
    simdjson: versions.simdjson,
    simdutf: versions.simdutf,
    sqlite: versions.sqlite,
    unicode: versions.unicode,
    uv: versions.uv,
    zlib: versions.zlib,
    zstd: versions.zstd,
  };
  for (const [name, value] of Object.entries(reported)) {
    assert.ok(value, `${name} reported no version`);
  }
});

console.log(`\n${failed.length === 0 ? 'all checks passed' : `${failed.length} check(s) failed`}`);
process.exitCode = failed.length === 0 ? 0 : 1;
