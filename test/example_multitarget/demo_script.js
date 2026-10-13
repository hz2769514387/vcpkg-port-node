// 场景七里两个目标共用的演示脚本：用 node 的 zlib（vcpkg 那一份）做一次
// 压/解往返，按调用方（process.argv[2]）打印标记。
//
// 两个目标（layered_app / direct_cli）跑的是同一个文件：脚本不关心谁调的
// node::Start，只认命令行 —— 这也是"分层不该渗进脚本"的意思。
const zlib = require('node:zlib');

const who = process.argv[2] || 'unknown';
const text = `multitarget-${who}`;
const back = zlib.inflateSync(zlib.deflateSync(text)).toString('utf8');

if (back !== text) {
  console.error(`MULTITARGET-FAIL ${who}: zlib 往返不一致`);
  process.exit(1);
}

console.log(`MULTITARGET-OK ${who} node=${process.versions.node}`);
