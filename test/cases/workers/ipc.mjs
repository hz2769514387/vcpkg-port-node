// child_process from inside an embedded runtime.
//
// fork() and spawn() use process.execPath, which only works if the embedding published its
// own executable path. An IPC channel is the part a job runner or a plugin host depends on:
// the parent sends work, the child sends a result, and both stay alive long enough to see it.
import assert from 'node:assert/strict';
import { once } from 'node:events';
import path from 'node:path';
import { fork, spawn, spawnSync } from 'node:child_process';

const script = path.join(import.meta.dirname, 'fork_script.cjs');

const quick = spawnSync(process.execPath,
  ['-e', 'process.stdout.write("child-ok")'], { encoding: 'utf8' });
assert.equal(quick.status, 0, quick.stderr);
assert.equal(quick.stdout, 'child-ok');

const streamed = spawn(process.execPath, ['-e', 'process.stdout.write("stream-ok")'],
  { stdio: ['ignore', 'pipe', 'pipe'] });
const chunks = [];
streamed.stdout.setEncoding('utf8');
streamed.stdout.on('data', (chunk) => chunks.push(chunk));
const [streamCode] = await once(streamed, 'close');
assert.equal(streamCode, 0);
assert.equal(chunks.join(''), 'stream-ok');
assert.ok(streamed.pid > 0);

const child = fork(script, [], {
  execPath: process.execPath,
  stdio: ['ignore', 'ignore', 'ignore', 'ipc'],
});
assert.ok(child.pid > 0);
const exited = once(child, 'exit');
child.send({ value: 21 });
const [reply] = await once(child, 'message');
assert.deepEqual(reply, { value: 42, from: 'ipc-child' });
child.send({ value: 'stop' });
const [exitCode] = await exited;
assert.equal(exitCode, 0);

console.log('workers: child processes and IPC ok');
