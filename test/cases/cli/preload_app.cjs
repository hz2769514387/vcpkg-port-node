// The application side of cli.preload: --require has to have run before this file.
const assert = require('node:assert/strict');
assert.equal(globalThis.__node_port_preloaded, 'yes');
console.log('cli: preload ok');
