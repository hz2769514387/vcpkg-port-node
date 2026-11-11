// Runs in each of the two environments. The host stamps the current iteration number onto
// the global before every uv_run; the timer records the iteration in which it fired, which
// is how the host knows the callback ran inside its own pump rather than in a loop Node.js
// started for itself.
const assert = require('node:assert/strict');

assert.ok(['A', 'B'].includes(globalThis.__node_port_owner));
globalThis.__node_port_owner_marker = globalThis.__node_port_owner;
setTimeout(() => {
  globalThis.__node_port_done = globalThis.__node_port_iteration;
}, 5);
