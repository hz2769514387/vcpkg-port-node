// Loaded inside a worker thread. The worker has its own isolate, so the module has to
// register itself again and resolve napi_* in this process.
import assert from 'node:assert/strict';
import { parentPort, threadId, workerData } from 'node:worker_threads';
import { createRequire } from 'node:module';

const addon = createRequire(import.meta.url)(workerData.addonPath);
assert.equal(addon.moduleVersion(), Number(process.versions.modules));
assert.equal(addon.sum(20), 210);

const result = await new Promise((resolve, reject) => {
  addon.asyncSum(50, (error, value) => (error ? reject(error) : resolve(value)));
});
assert.equal(result, 1275);
parentPort.postMessage({ threadId, result });
