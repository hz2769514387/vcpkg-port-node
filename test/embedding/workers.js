// worker_threads inside an embedded runtime.
//
// It is not enough that the runtime starts: an embedding that leaves out a platform, an
// isolate group or a message port still passes every "hello world" and then fails the
// first time a consumer actually uses Node.js the way Node.js is used. Worker threads are
// the cheapest probe for that, because they touch the isolate machinery, the message port
// and the event loop all at once.
const { Worker, isMainThread } = require('node:worker_threads');

if (isMainThread) {
  const worker = new Worker(
    `
    const { parentPort } = require('node:worker_threads');
    parentPort.postMessage('pong from the worker');
    `,
    { eval: true },
  );

  worker.on('message', (message) => {
    console.log(`main heard: ${message}`);
  });
  worker.on('error', (error) => {
    console.log(`worker failed: ${error.message}`);
    process.exitCode = 1;
  });
  worker.on('exit', (code) => {
    console.log(`worker exited with ${code}`);
  });
} else {
  // Only reached if the script is somehow run inside a worker as well.
  console.log('worker: unexpected branch');
  process.exitCode = 1;
}
