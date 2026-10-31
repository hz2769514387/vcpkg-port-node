// Keeps the runtime's event loop busy for a moment, so the host thread has something to
// overlap with. Without something like this the runtime would finish before the host loop
// could tick once, and the test would prove nothing.
const started = Date.now();
setTimeout(() => {
  console.log(`runtime: script finished after ${Date.now() - started} ms`);
}, 150);
