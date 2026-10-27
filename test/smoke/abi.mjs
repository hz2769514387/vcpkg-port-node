// The ABI numbers are the two things a consumer reads the config for without linking anything:
// NODE_MODULE_VERSION decides which prebuilt addon they may load, NAPI_VERSION which native API
// surface they may call. The port publishes both, and until this case existed nothing compared
// them with the runtime that was actually delivered.
//
// A wrong number does not fail here - it fails in the consumer, when an addon is rejected with
// "was compiled against a different Node.js version", which names neither this file nor this port.
import assert from 'node:assert';

const expectedModules = process.env.NODE_PORT_MODULE_VERSION;
const expectedNapi = process.env.NODE_PORT_NAPI_VERSION;
const expectedNapiMax = process.env.NODE_PORT_NAPI_VERSION_MAX;

assert.ok(expectedModules, 'ctest did not pass NODE_PORT_MODULE_VERSION - the exported config is '
  + 'missing node_MODULE_VERSION, or the environment line in test/smoke/CMakeLists.txt broke');
assert.ok(expectedNapi, 'ctest did not pass NODE_PORT_NAPI_VERSION - the exported config is '
  + 'missing node_NAPI_VERSION, or the environment line in test/smoke/CMakeLists.txt broke');

assert.strictEqual(
  String(process.versions.modules), expectedModules,
  `the config says NODE_MODULE_VERSION ${expectedModules}, the runtime reports ${process.versions.modules}`);
// process.versions.napi is the newest version the runtime supports, not the default a module gets.
// The port published those two as one number until this case existed; they are 10 and 8.
assert.strictEqual(
  String(process.versions.napi), expectedNapiMax,
  `the config says NAPI_VERSION_MAX ${expectedNapiMax}, the runtime reports ${process.versions.napi}`);
assert.ok(
  Number(expectedNapi) <= Number(expectedNapiMax),
  `the config says the default NAPI is ${expectedNapi}, above the maximum ${expectedNapiMax}`);

// The two must also be internally consistent: node's addon loader refuses anything else.
assert.ok(Number(process.versions.modules) > 0, 'process.versions.modules is not a number');

console.log(`abi ok: module ${expectedModules}, napi ${expectedNapi} of ${expectedNapiMax}, `
  + `node ${process.versions.node}`);
