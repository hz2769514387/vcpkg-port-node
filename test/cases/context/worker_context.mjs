// One worker of the pool: it keeps the job id in its own AsyncLocalStorage across an await.
import assert from 'node:assert/strict';
import { AsyncLocalStorage } from 'node:async_hooks';
import { parentPort, workerData } from 'node:worker_threads';

const als = new AsyncLocalStorage();

const seen = await als.run({ request: workerData.id }, async () => {
  await new Promise((resolve) => setTimeout(resolve, 1));
  return als.getStore()?.request;
});

assert.equal(seen, workerData.id);
parentPort.postMessage({ seen, outside: als.getStore() ?? null });
