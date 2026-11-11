// Run with --expose-gc, which is itself one of the things under test: V8's flags were
// parsed by node::Start and the platform is the one the host created.
import assert from 'node:assert/strict';
import v8 from 'node:v8';
import vm from 'node:vm';
import util from 'node:util';
import diagnostics_channel from 'node:diagnostics_channel';

assert.equal(typeof globalThis.gc, 'function', '--expose-gc did not reach V8');
const heap = v8.getHeapStatistics();
for (const key of ['total_heap_size', 'used_heap_size', 'heap_size_limit',
                   'number_of_native_contexts', 'total_available_size']) {
  assert.ok(Number.isFinite(heap[key]) && heap[key] > 0, `heap.${key} looks wrong: ${heap[key]}`);
}
globalThis.gc();
assert.ok(v8.getHeapStatistics().used_heap_size > 0);
assert.ok(v8.cachedDataVersionTag() > 0);

// A second V8 context with its own globals, and a timeout that has to interrupt a loop.
const sandbox = { a: 20, b: 22 };
assert.equal(vm.runInNewContext('a + b', sandbox), 42);
assert.equal(vm.isContext(vm.createContext({})), true);
assert.throws(() => vm.runInNewContext('while (true) {}', {}, { timeout: 50 }),
  /timed out|Script execution/i);

// WebAssembly compilation is a V8 pipeline, not a JavaScript library.
const emptyModule = new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0]);
assert.equal(WebAssembly.validate(emptyModule), true);
assert.equal(WebAssembly.validate(new Uint8Array([0, 0, 0, 0])), false);
assert.ok(await WebAssembly.compile(emptyModule) instanceof WebAssembly.Module);

// Buffer memory is shared with the underlying ArrayBuffer, not copied.
const backing = new ArrayBuffer(8);
const buffer = Buffer.from(backing);
buffer.writeUInt32LE(0x12345678, 0);
assert.equal(new Uint32Array(backing)[0], 0x12345678);
assert.equal(buffer.byteOffset, 0);

// Text decoding: ICU/simdutf-backed, with both the lenient and the fatal path.
assert.equal(new TextDecoder().decode(new Uint8Array([0xe4, 0xb8, 0xad])), '\u4e2d');
assert.throws(() => new TextDecoder('utf-8', { fatal: true })
  .decode(new Uint8Array([0xff])), TypeError);

// structuredClone preserves cycles and built-in collections.
const original = { name: 'graph' };
original.self = original;
original.values = new Map([['answer', 42]]);
const clone = structuredClone(original);
assert.equal(clone.self.name, 'graph');
assert.equal(clone.values.get('answer'), 42);
assert.notEqual(clone, original);

// Microtask queues and the utilities an embedding uses when it calls back into JS. Both
// queues drain before the next loop turn; their relative order inside an ESM module with
// top-level await is not a promise Node.js makes, so it is not asserted here.
const order = [];
process.nextTick(() => order.push('tick'));
queueMicrotask(() => order.push('microtask'));
await new Promise((resolve) => setImmediate(() => { order.push('immediate'); resolve(); }));
assert.deepEqual(order.slice(0, 2).sort(), ['microtask', 'tick']);
assert.equal(order[2], 'immediate');
assert.equal(util.types.isProxy(new Proxy({}, {})), true);
assert.equal(util.types.isDate(new Date()), true);
const controller = new AbortController();
controller.abort();
assert.equal(controller.signal.aborted, true);
assert.equal(diagnostics_channel.channel('node-port-probe').hasSubscribers, false);
assert.ok(process.hrtime.bigint() > 0n);
assert.ok(performance.now() >= 0);

console.log('runtime: V8 surface ok');
