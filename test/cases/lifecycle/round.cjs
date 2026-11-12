// Runs once per environment. The host stamps the round on globalThis before loading this
// file, and checks __node_port_round_ran afterwards, so a run in the wrong environment is
// visible to the C++ side rather than only to this script.
const assert = require('node:assert/strict');

assert.equal(typeof globalThis.__node_port_round, 'number');
assert.ok(globalThis.__node_port_round >= 1);
assert.equal(require('node:crypto').randomBytes(4).length, 4);
assert.ok(process.versions.modules > 0);
assert.match(process.argv[1], /round[.]cjs$/);
globalThis.__node_port_round_ran = true;
console.log(`lifecycle: environment ${globalThis.__node_port_round} ran`);
