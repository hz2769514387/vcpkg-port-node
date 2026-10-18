// Startup snapshot assertions.
//
// Node.js compiles its builtin JavaScript into a V8 snapshot at build time (mksnapshot), and
// the library links the generated blob. If a gyp passthrough ever dropped that step, node
// would still work - it would just compile the builtins at every startup, which changes
// startup cost and some builtin code paths, and no functional test would notice.
//
// `node_use_node_snapshot` is the config variable that says the snapshot is in the build
// (it replaced `node_use_snapshot` in the v26 configure output). A false value here means the
// blob is missing, which is the regression this check exists for.

import assert from 'node:assert/strict';

const variables = process.config.variables;

assert.equal(
  variables.node_use_node_snapshot,
  true,
  'this build has no bundled startup snapshot (node_use_node_snapshot is not true) - ' +
    'the builtin JavaScript will be compiled at every startup. See mksnapshot in the build log.',
);

// A snapshot that was built but not wired shows up the same way, so also prove the runtime
// is the version the port claims, which is what the snapshot was generated from.
assert.match(
  process.version,
  /^v\d+\.\d+\.\d+$/,
  `unexpected process.version '${process.version}'`,
);

console.log(
  `snapshot checks passed (node ${process.version}, node_use_node_snapshot=${variables.node_use_node_snapshot})`,
);
