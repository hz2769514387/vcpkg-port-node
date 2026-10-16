// The runtime's half of the cross-path zlib check.
//
// Run by the embedder - a consumer-linked Node.js runtime - against a workdir the C side has
// already filled with input.bin, c.deflate and c.meta. What this establishes:
//
//   * that the runtime's zlib is the Chromium fork (`process.versions.zlib`), which is the
//     claim the overlay port makes;
//   * that the runtime inflates what the C API compressed, and writes its own compression of
//     the same input back for the C side to inflate;
//   * that both paths compute the same crc32 over the same input.
//
// It deliberately does not require the two deflate outputs to be byte-identical: they share a
// library, not necessarily a code path into it. Whether they are is reported, because a sudden
// change there is worth noticing.
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');

const workdir = process.argv[2];
if (!workdir) {
  console.error('zlib_paths: no workdir argument');
  process.exit(2);
}
const file = (name) => path.join(workdir, name);

const input = fs.readFileSync(file('input.bin'));
const cDeflated = fs.readFileSync(file('c.deflate'));

const failures = [];
const check = (condition, description) => {
  console.log(`${condition ? 'ok   ' : 'FAIL '} ${description}`);
  if (!condition) {
    failures.push(description);
  }
};

console.log(`runtime zlib: ${process.versions.zlib}`);
check(/motley/.test(process.versions.zlib), 'the runtime reports the Chromium fork');

// The runtime inflates what the C API compressed.
const inflatedFromC = zlib.inflateSync(cDeflated);
check(inflatedFromC.equals(input), 'the runtime recovers the input from the C API output');

// And compresses the same input for the C side to inflate, plus a copy of what it saw about
// itself so the verdict does not rest on this process's stdout being parsed.
const deflatedHere = zlib.deflateSync(input, { level: 6 });
fs.writeFileSync(file('n.deflate'), deflatedHere);
fs.writeFileSync(
  file('n.meta'),
  `version=${process.versions.zlib}\n` +
    `crc32=${(zlib.crc32(input) >>> 0).toString(16).padStart(8, '0')}\n` +
    `n_deflate_size=${deflatedHere.length}\n`,
);

console.log(
  `note  deflate outputs are ${
    deflatedHere.equals(cDeflated) ? 'byte-identical' : 'different'
  } (runtime ${deflatedHere.length} bytes, C ${cDeflated.length} bytes)`,
);

if (failures.length > 0) {
  console.error(`zlib_paths: ${failures.length} check(s) failed`);
  process.exitCode = 1;
} else {
  console.log('zlib_paths: the runtime side agrees');
}
