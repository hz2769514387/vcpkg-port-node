'use strict';

// mutual.js —— "同进程互相操作"测试的 **JS 那一半**。
//
// 它由 mutual_roundtrip 可执行（**同一个进程**里也链着 vcpkg 的 zlib / openssl /
// sqlite3 / ada / simdjson）用 node::Start 跑起来。两边通过工作目录里的文件交接数据：
//
//   C++（vcpkg 库）        JS（node 运行时）
//   ────────────────      ─────────────────────────────
//   stage1.bin  (deflate)  →  解压、核对 sha256
//   stage1.sqlite          →  用 node:sqlite 读回同样的行
//   url.txt                →  用 new URL() 解析，输出同样的 host/pathname
//   ← stage2.json          （把上面所有结果写成 JSON 给 C++ 侧复核）
//
// 为什么这样能证明"共存"：两侧用的是**同一份**库（node 链接的就是 vcpkg 的那些：
// zlib / openssl / sqlite3 / ada / ICU…）。只要有一侧偷偷用了另一份拷贝（版本不同、
// 行为漂移），这里对照出来的值就会不一致。

const assert = require('node:assert');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');

const workdir = process.argv[2];
if (!workdir) {
  console.error('用法：node mutual.js <workdir>');
  process.exit(2);
}

const read = (f) => fs.readFileSync(path.join(workdir, f));
const write = (f, s) => fs.writeFileSync(path.join(workdir, f), s);

// ---- 1) C++ 侧用 vcpkg 的 zlib deflate 出来的数据，这里用 node 的 zlib 解压 ----
const expected = read('expected.txt').toString('utf8');   // 原文（C++ 侧写）
const deflated = read('stage1.bin');                      // vcpkg zlib 压缩结果
const inflated = zlib.inflateSync(deflated).toString('utf8');
assert.strictEqual(inflated, expected, 'node 解压 vcpkg 压缩的数据对不上');

// 反向：node 压缩一次，交给 C++ 侧（它回来后用 vcpkg zlib 解压校验）
write('stage2.deflate', zlib.deflateSync(Buffer.from(expected, 'utf8'), { level: 6 }));

// ---- 2) 摘要两侧必须一致（同一份 openssl）----
const sha256 = crypto.createHash('sha256').update(expected).digest('hex');

// ---- 3) URL：同一份 ada，两侧解析结果必须逐项相同 ----
const url = new URL(read('url.txt').toString('utf8').trim());
const urlParts = { hostname: url.hostname, pathname: url.pathname, search: url.search };

// ---- 4) node:sqlite 读 C++（vcpkg sqlite3）写出来的库 ----
let sqliteRows = [];
if (process.versions.sqlite) {
  const { DatabaseSync } = require('node:sqlite');
  const db = new DatabaseSync(path.join(workdir, 'stage1.sqlite'));
  sqliteRows = db.prepare('SELECT a, b FROM t ORDER BY a').all();
  db.close();
  assert.deepStrictEqual(sqliteRows, [{ a: 1, b: 'one' }, { a: 2, b: 'two' }],
                         'node:sqlite 读 vcpkg sqlite3 写的库，结果不对');
}

// ---- 5) ICU：大小写映射两侧一致 ----
const upper = '\u00df'.toUpperCase();   // ß -> SS

write('stage2.json', JSON.stringify({
  inflatedMatches: inflated === expected,
  sha256,
  urlParts,
  sqliteRows,
  nodeVersion: process.versions.node,
  sqliteVersion: process.versions.sqlite || '',
  zlibVersion: process.versions.zlib,
  opensslVersion: process.versions.openssl,
  icuVersion: process.versions.icu,
  upper,
}));

console.log('mutual.js: 完成（node ' + process.versions.node + '）');
