// A fixed workload, printed as a number, so two node binaries can be compared by running the
// same file rather than by parsing what Node.js's own benchmark directory happens to print this
// release (it moved from "N ops/sec" lines to JSON records, and that format is not this
// project's to depend on).
//
// Each case leans on a different piece of the C++ underneath - OpenSSL, zlib, V8's JSON path,
// the buffer implementation - which is exactly what differs between this port's build and the
// official binary. The JavaScript is identical for both, so it adds the same cost to each.
//
// Usage: node benchmark_workload.js <case>
// Prints one line: "<case> <milliseconds>"

'use strict';

const crypto = require('crypto');
const zlib = require('zlib');

const MiB = 1024 * 1024;

// 8 MiB of mixed bytes, built once and reused: the cases measure the operation, not the setup.
const bulk = Buffer.alloc(8 * MiB);
for (let i = 0; i < bulk.length; i += 1) bulk[i] = (i * 31 + 7) & 0xff;

const object = (() => {
  const rows = [];
  for (let i = 0; i < 20000; i += 1) {
    rows.push({ id: i, name: `row-${i}`, tags: ['a', 'b', 'c'], nested: { ok: i % 3 === 0, value: i / 7 } });
  }
  return rows;
})();

const cases = {
  hash() {
    for (let i = 0; i < 8; i += 1) crypto.createHash('sha256').update(bulk).digest();
  },
  gzip() {
    for (let i = 0; i < 8; i += 1) zlib.gzipSync(bulk, { level: 6 });
  },
  json() {
    for (let i = 0; i < 12; i += 1) JSON.parse(JSON.stringify(object));
  },
  buffer() {
    for (let i = 0; i < 64; i += 1) {
      const copy = Buffer.allocUnsafe(bulk.length);
      bulk.copy(copy);
      copy.fill(1, 0, 4096);
    }
  },
};

const name = process.argv[2];
if (!name || !cases[name]) {
  console.error(`usage: node benchmark_workload.js <${Object.keys(cases).join('|')}>`);
  process.exit(2);
}

const start = process.hrtime.bigint();
cases[name]();
const ms = Number(process.hrtime.bigint() - start) / 1e6;
process.stdout.write(`${name} ${ms.toFixed(1)}\n`);
