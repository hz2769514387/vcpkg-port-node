// Node.js parsed the flags the host put on its command line, rather than the host
// swallowing them before node::Start saw them.
import assert from 'node:assert/strict';
import v8 from 'node:v8';

const { execArgv } = process;
assert.ok(execArgv.includes('--expose-gc'), `execArgv: ${JSON.stringify(execArgv)}`);
assert.ok(execArgv.includes('--max-old-space-size=256'), `execArgv: ${JSON.stringify(execArgv)}`);
assert.equal(typeof globalThis.gc, 'function', '--expose-gc did not expose gc()');
assert.ok(process.allowedNodeEnvironmentFlags.has('--expose-gc'));

// 256 MB is a requested limit, not the exact resulting heap size: V8 adds the young
// generation and rounds up. The assertion is that the flag changed it into that range,
// which an ignored flag (the machine's default, often several GB) would not satisfy.
const limit = v8.getHeapStatistics().heap_size_limit;
assert.ok(limit >= 256 * 1024 * 1024 && limit < 1024 * 1024 * 1024,
  `--max-old-space-size was ignored: heap_size_limit=${limit}`);

console.log(`cli: flags ok (heap_size_limit=${limit})`);
