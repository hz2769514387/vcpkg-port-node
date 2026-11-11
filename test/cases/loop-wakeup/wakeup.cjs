// The loop has to stay alive long enough for the native thread to signal it, and the timer
// has to fire inside one of the host's uv_run(UV_RUN_NOWAIT) iterations. The host stamps
// the iteration number before every pump; this records the one in which the timer ran.
const assert = require('node:assert/strict');

assert.equal(typeof globalThis.__node_port_iteration, 'undefined');
setTimeout(() => {
  globalThis.__node_port_timer_at = globalThis.__node_port_iteration;
}, 30);
