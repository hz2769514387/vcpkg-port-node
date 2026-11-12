// Request-scoped state across every asynchronous boundary a service actually crosses, and
// the diagnostics channel an observability layer subscribes to.
//
// The assertion is not "getStore() returns an object". It is that the store survives each
// boundary, that two requests interleaved through the same event loop never see each other's
// store, and that a context captured earlier can be re-entered later - the three properties a
// request id in a log line depends on.
import assert from 'node:assert/strict';
import {
  AsyncLocalStorage, AsyncResource, createHook, executionAsyncId, triggerAsyncId,
} from 'node:async_hooks';
import diagnostics_channel from 'node:diagnostics_channel';
import { EventEmitter } from 'node:events';

const als = new AsyncLocalStorage();

// --- the store survives each boundary --------------------------------------
async function acrossBoundaries() {
  const seen = [];
  await als.run({ request: 'r1' }, async () => {
    const record = (label) => seen.push([label, als.getStore()?.request]);
    record('sync');
    await Promise.resolve();
    record('await');
    await Promise.all([Promise.resolve(), Promise.resolve()]);
    record('all');
    await new Promise((resolve) => setTimeout(resolve, 1));
    record('timeout');
    await new Promise((resolve) => setImmediate(resolve));
    record('immediate');
    await new Promise((resolve) => queueMicrotask(resolve));
    record('microtask');
    const emitter = new EventEmitter();
    await new Promise((resolve) => {
      emitter.on('tick', (value) => { seen.push(['event', value]); resolve(); });
      emitter.emit('tick', als.getStore()?.request);
    });
  });
  assert.ok(seen.every(([, value]) => value === 'r1'),
    `a boundary lost the store: ${JSON.stringify(seen)}`);
  assert.equal(seen.length, 7, `expected seven boundaries, saw ${seen.length}`);
  assert.equal(als.getStore(), undefined, 'the store leaked out of run()');
  return seen.length;
}

// --- two interleaved requests do not share a store --------------------------
async function concurrentRequests() {
  const observed = [];
  const task = (id) => als.run({ request: id }, async () => {
    for (let step = 0; step < 3; step += 1) {
      await new Promise((resolve) => setTimeout(resolve, 1));
      observed.push([id, als.getStore()?.request]);
    }
  });
  await Promise.all([task('request-a'), task('request-b')]);
  assert.ok(observed.every(([id, seen]) => id === seen),
    `stores crossed between requests: ${JSON.stringify(observed)}`);
  return observed.length;
}

// --- a captured context can be re-entered later -----------------------------
function snapshotReentry() {
  const restore = als.run({ request: 'snapshot' }, () => AsyncLocalStorage.snapshot());
  assert.equal(als.getStore(), undefined);
  const reentered = restore(() => als.getStore()?.request);
  assert.equal(reentered, 'snapshot');
  assert.equal(als.getStore(), undefined);
  return reentered;
}

// --- an AsyncResource carries the context it was created in -----------------
function asyncResourceCarriesContext() {
  let resource;
  als.run({ request: 'resource' }, () => { resource = new AsyncResource('node-port:context'); });
  assert.equal(als.getStore(), undefined);
  assert.equal(resource.runInAsyncScope(() => als.getStore()?.request), 'resource');
  return 'resource';
}

// --- async ids and hooks ----------------------------------------------------
async function asyncIdsAndHooks() {
  const timerId = await new Promise((resolve) => setImmediate(() => resolve(executionAsyncId())));
  assert.ok(timerId > 0, `executionAsyncId() in a callback was ${timerId}`);
  assert.ok(triggerAsyncId() >= 0);

  let inits = 0;
  const hook = createHook({ init() { inits += 1; } }).enable();
  try {
    await new Promise((resolve) => setTimeout(resolve, 1));
    await Promise.resolve();
  } finally {
    hook.disable();
  }
  assert.ok(inits > 0, 'async_hooks saw no resources for a timer and a promise');
  return inits;
}

// --- diagnostics_channel: pub/sub and the tracing wrapper -------------------
function diagnostics() {
  const channel = diagnostics_channel.channel('node-port:requests');
  const messages = [];
  const onMessage = (message) => messages.push(message);
  channel.subscribe(onMessage);
  try {
    assert.equal(channel.hasSubscribers, true);
    channel.publish({ id: 7, route: '/orders' });
  } finally {
    channel.unsubscribe(onMessage);
  }
  assert.deepEqual(messages, [{ id: 7, route: '/orders' }]);
  assert.equal(channel.hasSubscribers, false);

  const tracing = diagnostics_channel.tracingChannel('node-port:work');
  const events = [];
  const handlers = {
    start() { events.push('start'); },
    end() { events.push('end'); },
    asyncStart() {},
    asyncEnd() {},
    error() {},
  };
  tracing.subscribe(handlers);
  let value;
  try {
    value = tracing.traceSync((a, b) => a + b, { name: 'add' }, null, 20, 22);
  } finally {
    tracing.unsubscribe(handlers);
  }
  assert.equal(value, 42);
  assert.deepEqual(events, ['start', 'end']);
  return `${channel.name}`;
}

const boundaries = await acrossBoundaries();
const interleaved = await concurrentRequests();
snapshotReentry();
asyncResourceCarriesContext();
const hooks = await asyncIdsAndHooks();
diagnostics();
console.log(`context: async local storage and diagnostics ok ` +
  `(${boundaries} boundaries, ${interleaved} interleaved, ${hooks} hook events)`);
