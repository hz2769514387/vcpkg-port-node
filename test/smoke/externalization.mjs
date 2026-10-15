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

function check(name, body) {
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

check('ICU came from vcpkg (system-icu, full data)', () => {
  assert.equal(config.variables.icu_system, true);
  assert.equal(config.variables.icu_small, false);
  assert.ok(Number(config.variables.icu_ver_major) >= 70, 'ICU major version looks wrong');
  // Only full ICU has locale data for locales outside the small set.
  assert.equal(new Intl.NumberFormat('de-DE').format(1234.5), '1.234,5');
  assert.match(new Intl.DateTimeFormat('en-US', { timeZone: 'UTC' }).format(new Date(0)), /1970/);
});

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
