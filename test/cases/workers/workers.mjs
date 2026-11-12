// A small worker pool: three isolates, one SharedArrayBuffer, and an accounting check.
import assert from 'node:assert/strict';
import { once } from 'node:events';
import path from 'node:path';
import {
  isMainThread, MessageChannel, receiveMessageOnPort, threadId, Worker,
} from 'node:worker_threads';

assert.equal(isMainThread, true);
// The main thread's worker_threads id is 0; each worker gets a positive one.
assert.equal(threadId, 0);

const script = path.join(import.meta.dirname, 'worker_script.mjs');
const shared = new Int32Array(new SharedArrayBuffer(Int32Array.BYTES_PER_ELEMENT));
const workers = [];
const exits = [];
const replies = [];

for (let id = 1; id <= 3; id += 1) {
  const worker = new Worker(script, { workerData: { id, shared } });
  workers.push(worker);
  // Registered before the worker can finish, so a fast worker cannot beat the listener.
  exits.push(once(worker, 'exit'));
  replies.push(once(worker, 'message'));
}

const messages = await Promise.all(replies);
const codes = await Promise.all(exits);
for (const [code] of codes) assert.equal(code, 0, 'a worker did not exit cleanly');
const results = messages.map(([message]) => message).sort((a, b) => a.id - b.id);
assert.deepEqual(results.map((entry) => entry.id), [1, 2, 3]);
assert.deepEqual(results.map((entry) => entry.square), [1, 4, 9]);

// Each worker incremented the same counter in shared memory; a build that gave every
// worker its own copy of the buffer would leave this at zero.
assert.equal(Atomics.load(shared, 0), 14);

// MessagePort is the other half of worker_threads: a channel between two ports without
// going through parentPort at all.
const { port1, port2 } = new MessageChannel();
port2.on('message', (value) => port2.postMessage(value * 2));
port1.postMessage(21);
const [answer] = await once(port1, 'message');
assert.equal(answer, 42);
port1.close();
port2.close();

const sync = new MessageChannel();
sync.port2.postMessage('sync');
assert.equal(receiveMessageOnPort(sync.port1).message, 'sync');
sync.port1.close();
sync.port2.close();

console.log('workers: pool, shared memory and message ports ok');
