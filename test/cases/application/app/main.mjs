// The entry point of the application fixture.
//
// Each assertion is a different part of Node.js's module loader the embedding has to carry:
// static ESM, CommonJS through createRequire, a bare package specifier, a JSON module with an
// import attribute, a dynamic import, and a top-level await before any of it finishes. A host
// that only got node::Start() linked would still start; it is the loader, the builtins and the
// snapshot that decide whether these resolve.
import assert from 'node:assert/strict';
import data from './data.json' with { type: 'json' };
import { greet } from './lib/greeter.mjs';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const require = createRequire(import.meta.url);

assert.equal(data.answer, 42);
assert.equal(greet('world'), 'hello world');
assert.equal(require('./lib/legacy.cjs')(21), 42);
assert.equal(require('fixture-pkg').label, 'fixture-pkg');
assert.equal(require('fixture-pkg').double(21), 42);

const lazy = await import('./lib/lazy.mjs');
assert.equal(await lazy.compute(6), 36);

// On Windows an absolute path passed to import() is parsed as a URL with a drive-letter
// scheme and rejected, so a file: URL is the form that works on every platform.
const dynamic = await import(
  pathToFileURL(path.join(import.meta.dirname, 'data.json')).href,
  { with: { type: 'json' } });
assert.equal(dynamic.default.answer, 42);

assert.ok(import.meta.url.startsWith('file:'));
assert.equal(path.basename(new URL(import.meta.url).pathname), 'main.mjs');

console.log('application: module graph ok');
