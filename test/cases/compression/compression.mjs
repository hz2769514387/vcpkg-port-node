// Sync and stream round trips for every codec Node.js exposes through node:zlib.
// The payload is repetitive on purpose: an empty or single-byte payload would pass even
// if the codec returned its input unchanged.
import assert from 'node:assert/strict';
import { Readable, Writable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import zlib from 'node:zlib';

const payload = Buffer.from(('a business payload with repetition '.repeat(200)) + 'end');
const { versions } = process;
for (const name of ['zlib', 'brotli', 'zstd']) {
  assert.ok(versions[name], `process.versions.${name} is missing`);
}

const codecs = [
  ['gzip', zlib.gzipSync, zlib.gunzipSync, zlib.createGzip, zlib.createGunzip],
  ['deflate', zlib.deflateSync, zlib.inflateSync, zlib.createDeflate, zlib.createInflate],
  ['brotli', zlib.brotliCompressSync, zlib.brotliDecompressSync,
   zlib.createBrotliCompress, zlib.createBrotliDecompress],
  ['zstd', zlib.zstdCompressSync, zlib.zstdDecompressSync,
   zlib.createZstdCompress, zlib.createZstdDecompress],
];

for (const [name, compress, decompress, createCompress, createDecompress] of codecs) {
  const compressed = compress(payload);
  assert.ok(compressed.length < payload.length,
    `${name} did not compress a repetitive payload (${compressed.length} vs ${payload.length})`);
  assert.deepEqual(decompress(compressed), payload, `${name} sync round trip`);

  const chunks = [];
  const sink = new Writable({
    write(chunk, encoding, callback) { chunks.push(chunk); callback(); },
  });
  await pipeline(
    Readable.from([payload.subarray(0, 100), payload.subarray(100)]),
    createCompress(),
    createDecompress(),
    sink);
  assert.deepEqual(Buffer.concat(chunks), payload, `${name} stream round trip`);
}

// A truncated zlib stream must fail loudly rather than silently returning a short buffer:
// that is the error path a consumer's decompression pipeline depends on.
assert.throws(() => zlib.gunzipSync(zlib.gzipSync(payload).subarray(0, 12)));

console.log(`compression: ${codecs.length} codecs ok (zlib ${versions.zlib}, ` +
  `brotli ${versions.brotli}, zstd ${versions.zstd})`);
