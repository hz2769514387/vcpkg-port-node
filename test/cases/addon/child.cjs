// Loaded in a separate process started from process.execPath by the embedder.
const assert = require('node:assert/strict');
const addon = require(process.argv[2]);

assert.equal(addon.moduleVersion(), Number(process.versions.modules));
assert.equal(addon.sum(30), 465);
process.send({ pid: process.pid, result: addon.sum(30) });
process.disconnect();
