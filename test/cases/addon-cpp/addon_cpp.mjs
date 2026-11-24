// Loads the addon this project just built and exercises the class the wrapper registered.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import fs from 'node:fs';

const addonPath = process.argv[2];
assert.ok(addonPath && fs.existsSync(addonPath), `addon path is missing: ${addonPath}`);
const { Counter } = createRequire(import.meta.url)(addonPath);

const counter = new Counter(10);
assert.equal(counter.value, 10);
assert.equal(counter.increment(5), 15);
assert.equal(counter.increment(), 16);
assert.equal(counter.value, 16);

console.log('addon-cpp: node-addon-api wrapper ok');
