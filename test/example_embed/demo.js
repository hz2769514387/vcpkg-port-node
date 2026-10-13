// 示例 example_embed 自带的用例：由本目录编出来的 node 运行时执行，
// 演示"消费方怎么给嵌进去的运行时写测试"（和平时的 `node xxx.js` 一样）。
'use strict';
const assert = require('node:assert');

// 嵌进来的运行时该有的东西都在：process / require / Buffer …
assert.strictEqual(typeof process.versions.v8, 'string');
assert.strictEqual(typeof Buffer.alloc(4).length, 'number');

// 顺手用一次 libuv 那侧的能力：定时器真的会走事件循环（不是空转退出）。
setTimeout(() => {
  process.stdout.write('EMBED-DEMO-OK\n');
}, 0);
