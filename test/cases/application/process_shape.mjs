// What a host application reads off `process` before it does any work.
//
// `execPath` is the assertion that matters most: it says the JavaScript is running in the
// executable this project linked, not in the node.exe the port also installs. Everything else
// is an input the host supplied - argv, cwd, environment - or a fact it needs in order to pick
// a compatible native addon.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const { argv, execArgv, env, versions, config } = process;

assert.ok(fs.statSync(process.execPath).isFile(), 'process.execPath is not a file');
assert.match(path.basename(process.execPath), /^node_embed/,
  'the script did not run in the consumer-linked embedder');
assert.ok(fs.statSync(process.argv[0]).isFile(), 'process.argv[0] is not a file');
assert.equal(path.basename(argv[1]), 'process_shape.mjs');
assert.ok(path.isAbsolute(process.cwd()));
assert.ok(fs.statSync(process.cwd()).isDirectory());

assert.equal(env.NODE_PORT_SENTINEL, 'from-ctest', 'the ctest environment did not reach the runtime');
assert.equal(versions.node, env.NODE_PORT_EXPECTED_VERSION,
  'the version the exported config publishes is not the version this runtime reports');
assert.equal(String(versions.modules), env.NODE_PORT_EXPECTED_MODULES,
  'the NODE_MODULE_VERSION the config publishes is not the one this runtime reports');
assert.ok(Array.isArray(execArgv));
assert.ok(['win32', 'linux', 'darwin'].includes(process.platform));
assert.ok(['x64', 'arm64', 'ia32', 'arm'].includes(process.arch));
assert.ok(process.uptime() >= 0);
assert.ok(process.memoryUsage().rss > 0);
assert.equal(config.variables.icu_system, true);

// Both microtask queues are drained before the next turn of the loop. Their relative order
// depends on whether the entry point is ESM with a top-level await, so the assertion is
// about the loop turn, not about which queue V8 happened to drain first.
const order = [];
process.nextTick(() => order.push('tick'));
Promise.resolve().then(() => order.push('promise'));
await new Promise((resolve) => setImmediate(() => { order.push('immediate'); resolve(); }));
assert.deepEqual(order.slice(0, 2).sort(), ['promise', 'tick']);
assert.equal(order[2], 'immediate');

console.log('application: process shape ok');
