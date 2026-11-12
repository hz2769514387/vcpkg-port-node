// The same addon, loaded in the two places a product puts native work: a worker thread and
// a forked child process.
//
// A worker has its own isolate and its own module registry inside one process; a child is a
// separate process started from process.execPath. Both have to find the N-API implementation
// again, and both are common places for a packaging mistake to show up only in production.
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { Worker } from 'node:worker_threads';
import { fork } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const addonPath = process.argv[2];
assert.ok(addonPath, 'the addon path is missing');

const worker = new Worker(new URL('./worker.mjs', import.meta.url), {
  workerData: { addonPath },
});
const [workerMessage] = await once(worker, 'message');
assert.equal(workerMessage.result, 1275);
assert.ok(workerMessage.threadId > 0, 'the worker reported no thread id');
await worker.terminate();

const childScript = fileURLToPath(new URL('./child.cjs', import.meta.url));
const child = fork(childScript, [addonPath], {
  execPath: process.execPath,
  stdio: ['ignore', 'ignore', 'ignore', 'ipc'],
});
// Registered before the message: the child disconnects as soon as it has answered, so it
// can be gone before a listener added afterwards would see 'exit'. Waiting for it keeps a
// stray process from overlapping the next ctest case and stealing CPU from its timers.
const childExited = once(child, 'exit');
const [childMessage] = await once(child, 'message');
assert.equal(childMessage.result, 465);
assert.notEqual(childMessage.pid, process.pid, 'the child shares the parent pid');
await childExited;

console.log('addon: worker thread and child process ok');
