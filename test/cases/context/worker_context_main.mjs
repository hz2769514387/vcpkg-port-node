// Two workers, each with its own AsyncLocalStorage store, running at the same time.
//
// A worker pool that carries a job id through its native work depends on two properties: the
// store is per isolate, and it survives the awaits inside the worker. Neither is implied by
// the single-threaded case.
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { Worker } from 'node:worker_threads';

const workers = ['job-a', 'job-b'].map((id) => {
  const worker = new Worker(new URL('./worker_context.mjs', import.meta.url), {
    workerData: { id },
  });
  return { id, worker, message: once(worker, 'message'), exit: once(worker, 'exit') };
});

for (const entry of workers) {
  const [message] = await entry.message;
  assert.equal(message.seen, entry.id,
    `worker ${entry.id} saw ${message.seen}; the stores crossed isolates`);
  assert.equal(message.outside, null, 'a worker saw a store outside its run()');
  const [code] = await entry.exit;
  assert.equal(code, 0, `worker ${entry.id} exited with ${code}`);
}

console.log('context: per-worker stores ok');
