'use strict';

// 共存行为测试（由 test 工程自己链接出来的 node 嵌入可执行运行）。
//
// 目的：把"由第三方库提供的 node 能力"逐个真跑一遍。只要其中任何一个 vcpkg 库
// 与 node port 不兼容（符号被错解、ABI 不符、行为漂移），这里就会红：
//
//   zlib / brotli      <- vcpkg zlib、vcpkg brotli（v8 内嵌 zlib 已并入前者）
//   crypto             <- vcpkg openssl
//   Intl               <- vcpkg icu
//   URL / IDN          <- vcpkg ada-url（含 ada-idna）
//   node:sqlite        <- vcpkg sqlite3
//   http               <- vcpkg llhttp（HTTP 解析器）
//   http2              <- vcpkg nghttp2（h2c，无需 TLS）
//   worker_threads     <- vcpkg libuv（线程/事件循环）
//   WebAssembly        <- V8（即 node 自身体量最大的那部分）
//
// 全部通过后打印 COEXIST-OK（ctest 用它作成功判据）。

const assert = require('node:assert');
const crypto = require('node:crypto');
const http = require('node:http');
const http2 = require('node:http2');
const zlib = require('node:zlib');
const { URL } = require('node:url');
const { Worker } = require('node:worker_threads');

const SAMPLE = 'The quick brown fox jumps over the lazy dog.';
const notes = [];

function note(text) {
  notes.push(text);
  console.log('  ok  ' + text);
}

async function checkZlib() {
  const gz = zlib.gzipSync(SAMPLE);
  assert.strictEqual(zlib.gunzipSync(gz).toString(), SAMPLE);
  const br = zlib.brotliCompressSync(SAMPLE);
  assert.strictEqual(zlib.brotliDecompressSync(br).toString(), SAMPLE);
  assert.ok(process.versions.zlib, 'process.versions.zlib 为空');
  assert.ok(process.versions.brotli, 'process.versions.brotli 为空');
  note(`zlib ${process.versions.zlib} / brotli ${process.versions.brotli} 压缩往返`);
}

function checkCrypto() {
  const digest = crypto.createHash('sha256').update('abc').digest('hex');
  assert.strictEqual(
      digest,
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  const hmac = crypto.createHmac('sha256', 'k').update('m').digest('hex');
  assert.strictEqual(hmac.length, 64);
  assert.strictEqual(crypto.randomBytes(16).length, 16);
  assert.ok(process.versions.openssl, 'process.versions.openssl 为空');
  note(`openssl ${process.versions.openssl} sha256/hmac/random`);
}

function checkIcu() {
  assert.strictEqual(
      new Intl.NumberFormat('de-DE').format(1234567.89), '1.234.567,89');
  // 德国 7.89 -> "1.234.567,89"；这条同时验证 ICU 数据可用
  assert.strictEqual('\u00df'.toUpperCase(), 'SS');   // ß -> SS（ICU 的 case 映射）
  assert.ok(new Intl.DateTimeFormat('ja-JP').format(new Date(0)).length > 0);
  assert.ok(process.versions.icu, 'process.versions.icu 为空');
  note(`icu ${process.versions.icu} 数字/日期/大小写`);
}

function checkAdaIdna() {
  // 非 ASCII 域名 -> punycode，走的是 ada-url + idna 数据
  assert.strictEqual(
      new URL('https://b\u00fccher.example/path').hostname, 'xn--bcher-kva.example');
  assert.ok(process.versions.ada, 'process.versions.ada 为空');
  note(`ada ${process.versions.ada} IDN 归一`);
}

function checkSqlite() {
  if (!process.versions.sqlite) {
    note('sqlite 未编译进这份 node（跳过）');
    return;
  }
  const { DatabaseSync } = require('node:sqlite');
  const db = new DatabaseSync(':memory:');
  db.exec('CREATE TABLE t(a INTEGER, b TEXT)');
  db.exec("INSERT INTO t VALUES (42, 'x')");
  const row = db.prepare('SELECT a, b FROM t').get();
  assert.strictEqual(row.a, 42);
  assert.strictEqual(row.b, 'x');
  db.close();
  note(`sqlite ${process.versions.sqlite} 建表/写入/查询`);
}

function checkHttp() {
  return new Promise((resolve, reject) => {
    const server = http.createServer((req, res) => {
      res.writeHead(200, { 'content-type': 'text/plain' });
      res.end('hello-llhttp');
    });
    server.listen(0, '127.0.0.1', () => {
      const { port } = server.address();
      http.get({ host: '127.0.0.1', port, path: '/' }, (res) => {
        let body = '';
        res.setEncoding('utf8');
        res.on('data', (c) => { body += c; });
        res.on('end', () => {
          server.close();
          try {
            assert.strictEqual(res.statusCode, 200);
            assert.strictEqual(body, 'hello-llhttp');
            note('http 往返（llhttp 解析器）');
            resolve();
          } catch (e) { reject(e); }
        });
      }).on('error', reject);
    });
  });
}

function checkHttp2() {
  return new Promise((resolve, reject) => {
    const server = http2.createServer();
    server.on('stream', (stream) => {
      stream.respond({ ':status': 200, 'content-type': 'text/plain' });
      stream.end('hello-nghttp2');
    });
    server.listen(0, '127.0.0.1', () => {
      const { port } = server.address();
      const client = http2.connect(`http://127.0.0.1:${port}`);
      const req = client.request({ ':path': '/' });
      let body = '';
      req.setEncoding('utf8');
      req.on('data', (c) => { body += c; });
      req.on('end', () => {
        client.close();
        server.close();
        try {
          assert.strictEqual(body, 'hello-nghttp2');
          note(`http2 往返（nghttp2 ${process.versions.nghttp2}）`);
          resolve();
        } catch (e) { reject(e); }
      });
      req.on('error', reject);
      req.end();
    });
  });
}

function checkWorkerThreads() {
  return new Promise((resolve, reject) => {
    const worker = new Worker(
        'const { parentPort } = require("node:worker_threads");' +
        'parentPort.postMessage(21 * 2);',
        { eval: true });
    worker.once('message', (value) => {
      try {
        assert.strictEqual(value, 42);
        note('worker_threads（libuv 线程）');
        resolve();
      } catch (e) { reject(e); }
    });
    worker.once('error', reject);
  });
}

async function checkWasm() {
  // 最小合法 wasm 模块：magic + version
  const bytes = new Uint8Array([0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]);
  const module = await WebAssembly.compile(bytes);
  const instance = await WebAssembly.instantiate(module, {});
  assert.ok(instance, 'wasm 实例为空');
  note(`WebAssembly（V8 ${process.versions.v8}）`);
}

(async () => {
  console.log('共存行为测试：node ' + process.versions.node + ' @ ' + process.execPath);
  try {
    await checkZlib();
    checkCrypto();
    checkIcu();
    checkAdaIdna();
    checkSqlite();
    await checkHttp();
    await checkHttp2();
    await checkWorkerThreads();
    await checkWasm();
  } catch (err) {
    console.error('\n共存测试失败：');
    console.error(err && err.stack ? err.stack : err);
    process.exit(1);
  }
  console.log('\n--- node 报告的依赖版本 ---');
  for (const key of ['node', 'v8', 'uv', 'zlib', 'brotli', 'zstd', 'ares',
                     'nghttp2', 'llhttp', 'openssl', 'icu', 'unicode', 'sqlite',
                     'simdutf', 'simdjson', 'ada', 'ngtcp2', 'nghttp3', 'uvwasi']) {
    if (process.versions[key]) console.log(`  ${key}: ${process.versions[key]}`);
  }
  console.log(`\n共 ${notes.length} 项行为检查通过`);
  console.log('COEXIST-OK');
})();
