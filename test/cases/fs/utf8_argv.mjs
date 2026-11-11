// A non-ASCII argument supplied by the host process.
//
// On Windows the embedder enters through wmain and converts wargv to UTF-8 itself; a host
// using main(char**) would get the system ANSI code page's interpretation instead. CMake
// builds this argument from UTF-8 byte values, ctest hands it to the process, and the
// assertion compares it with the same three code points in JavaScript.
import assert from 'node:assert/strict';

const expected = '\u4e2d\u6587-1';
assert.equal(process.argv.length, 3, `unexpected argv: ${JSON.stringify(process.argv)}`);
assert.equal(process.argv[2], expected,
  `the host's argument did not survive as UTF-8: ${JSON.stringify(process.argv[2])}`);
assert.equal(Buffer.from(process.argv[2], 'utf8').toString('hex'), 'e4b8ade696872d31');
console.log('fs: utf8 argv ok');
