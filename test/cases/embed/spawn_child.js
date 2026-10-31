// Spawning a child Node process from an embedded runtime.
//
// process.execPath in an embedded runtime is the host executable, not node.exe - which is
// exactly why this is a useful test: the child is spawned with the same argv semantics the
// runtime itself was given, so it doubles as a check that the embedding is a faithful
// shell. A consumer that shells out to node for a build step or a linter depends on this.
const { spawnSync } = require('node:child_process');

const child = spawnSync(process.execPath, ['-p', 'process.versions.node'], {
  encoding: 'utf8',
});

if (child.error) {
  console.log(`spawn failed: ${child.error.message}`);
  process.exitCode = 1;
} else if (child.status !== 0) {
  console.log(`child exited with ${child.status}: ${child.stderr}`);
  process.exitCode = 1;
} else {
  console.log(`child reported node ${child.stdout.trim()}`);
}
