// 场景五里 node 那一侧的脚本。既然子进程都跑起来了，顺手真做点活：
// 用 node 的 zlib 把一段已知文本压一遍再解回来，逐字节核对。
//
// 为什么挑 zlib：node 的 zlib 就是 **vcpkg 提供的那一份**（port 的核心
// 承诺之一）—— 子进程这条使用路径上，库同样是 vcpkg 的，不是系统自带的。
const zlib = require('node:zlib');

const text = 'spawn-child-zlib-roundtrip';
const packed = zlib.deflateSync(text);
const back = zlib.inflateSync(packed).toString('utf8');

if (back !== text) {
  console.error(`SPAWN-CHILD-FAIL: zlib 往返不一致：${back}`);
  process.exit(1);
}

console.log(
  `SPAWN-CHILD-OK node=${process.versions.node} zlib-roundtrip=${back.length}B`
);
