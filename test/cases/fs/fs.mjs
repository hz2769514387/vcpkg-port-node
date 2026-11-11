// Filesystem operations an application actually performs, on paths that are not plain
// ASCII identifiers. Non-ASCII names are written as escapes so this tracked file stays
// ASCII; the runtime still sees real multi-byte UTF-8 filenames.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { pipeline } from 'node:stream/promises';

const root = process.argv[2];
if (!root) throw new Error('the test needs a work directory as its first argument');

// A failed earlier run must not leave evidence that lets this run pass without doing the
// work: the fixture directory is removed and recreated at the start.
fs.rmSync(root, { recursive: true, force: true });
fs.mkdirSync(root, { recursive: true });

const names = [
  'plain.txt',
  'with spaces (1).txt',
  'hash#plus+paren.txt',
  '\u4e2d\u6587.txt',
  '\u{1F680}.bin',
];
const content = 'a payload with \u4e2d\u6587 content and a trailing marker\n';

for (const name of names) {
  fs.writeFileSync(path.join(root, name), content, 'utf8');
  assert.equal(fs.readFileSync(path.join(root, name), 'utf8'), content, `read ${name}`);
}
assert.deepEqual(fs.readdirSync(root).sort(), [...names].sort());
assert.ok(fs.statSync(path.join(root, names[0])).isFile());
assert.ok(fs.existsSync(fs.realpathSync(path.join(root, names[0]))));

// The promises API and a stream copy are different code paths from the sync ones.
const promised = path.join(root, 'promised.txt');
await fs.promises.writeFile(promised, content, 'utf8');
assert.equal(await fs.promises.readFile(promised, 'utf8'), content);
const copied = path.join(root, 'copied.txt');
await pipeline(fs.createReadStream(path.join(root, names[0])), fs.createWriteStream(copied));
assert.equal(fs.readFileSync(copied, 'utf8'), content);

// Recursive copy carries every name, including the non-ASCII ones.
const mirror = `${root}-mirror`;
fs.rmSync(mirror, { recursive: true, force: true });
fs.cpSync(root, mirror, { recursive: true });
for (const name of [...names, 'promised.txt', 'copied.txt']) {
  assert.ok(fs.existsSync(path.join(mirror, name)), `cpSync lost ${name}`);
}

// Symlinks are a capability, not a platform: a plain Windows shell without Developer
// Mode cannot create one, while CI images and Unix can (cases/suite uses the same probe).
let symlinks = true;
try {
  const link = path.join(root, 'link.txt');
  fs.symlinkSync(names[0], link, 'file');
  assert.ok(fs.lstatSync(link).isSymbolicLink());
  assert.equal(fs.readFileSync(link, 'utf8'), content);
} catch (error) {
  if (!['EPERM', 'EACCES', 'ENOSYS', 'ENOTSUP'].includes(error.code)) throw error;
  symlinks = false;
}

fs.rmSync(root, { recursive: true, force: true });
fs.rmSync(mirror, { recursive: true, force: true });
console.log(`fs: paths and streams ok (symlinks ${symlinks ? 'available' : 'not permitted here'})`);
