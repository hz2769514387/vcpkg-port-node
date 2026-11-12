// Loads the addon this project just built and exercises it the way a product would.
//
// The path comes from argv because the module is a CMake target, not a file in this
// directory. createRequire() is what an ESM application uses to load a .node module.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import fs from 'node:fs';

const addonPath = process.argv[2];
assert.ok(addonPath && fs.existsSync(addonPath), `addon path is missing: ${addonPath}`);
const addon = createRequire(import.meta.url)(addonPath);

// The NODE_MODULE_VERSION baked into the installed headers must be the one the runtime
// reports. A wrong number here is the failure a prebuilt addon sees as "was compiled
// against a different Node.js version".
// process.versions.modules and .napi are strings; the addon returns numbers.
assert.equal(addon.moduleVersion(), Number(process.versions.modules));
const info = addon.runtimeInfo();
assert.equal(info.node, process.versions.node);
assert.ok(info.napi >= 8, `N-API version ${info.napi} is too low`);
assert.equal(String(info.napi), process.versions.napi);

assert.equal(addon.sum(10), 55);
assert.equal(addon.sum(0), 0);
assert.equal(addon.callWith((n) => n * 2, 21), 42);
const buffer = addon.makeBuffer('from-native-memory');
assert.ok(Buffer.isBuffer(buffer));
assert.equal(buffer.toString('utf8'), 'from-native-memory');
assert.throws(() => addon.throwExample('expected failure'), /expected failure/);

// Async work runs on libuv's thread pool and calls back on the JS thread. A build with a
// second, uncoordinated libuv copy would either never call back or hang the loop.
const asyncResult = await new Promise((resolve, reject) => {
  const timer = setTimeout(() => reject(new Error('addon_error: asyncSum never called back')), 20000);
  addon.asyncSum(100, (error, value) => {
    clearTimeout(timer);
    if (error) reject(error);
    else resolve(value);
  });
});
assert.equal(asyncResult, 5050);

// A std::thread the runtime knows nothing about calls into JavaScript through a
// thread-safe function. This is the native-producer / JS-consumer pattern, and it proves
// the loop keeps running until the producer releases its last reference.
const streamed = await new Promise((resolve, reject) => {
  const seen = [];
  const timer = setTimeout(
    () => reject(new Error(`addon_error: stream delivered ${seen.length} of 5 values`)), 20000);
  addon.streamFromThread(5, (value) => {
    seen.push(value);
    if (seen.length === 5) {
      clearTimeout(timer);
      resolve(seen);
    }
  });
});
assert.deepEqual(streamed, [1, 2, 3, 4, 5]);

console.log(`addon: N-API module ok (module ${addon.moduleVersion()}, N-API ${info.napi})`);
