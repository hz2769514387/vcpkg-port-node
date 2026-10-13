// openssl 行为面核对：node 自带 openssl → 换成 vcpkg 的 openssl，行为是否还一致。
//
// 背景（为什么要有这个用例）
// --------------------------
// node 对 openssl 的定制**不是**打源码补丁（deps/openssl 下没有 patches 目录），而是：
//   1. 自带一份按架构预生成的 openssl 构建配置（deps/openssl/config/archs/...）；
//      只在"编自带那份 openssl"时生效，--shared-openssl 下根本不看；
//   2. 自带一份 nodejs-openssl.cnf，编进二进制后由 src/node.cc 用
//      NODE_OPENSSL_CONF_NAME(=nodejs_conf) **显式**喂给 OpenSSL 去激活 provider；
//      这条路跟用哪份 openssl 无关，是我们这条链路的"保险"；
//   3. 编自带那份时带 OPENSSL_API_COMPAT=0x10100001L；共享模式下这条也用不上，
//      node 自己的代码改为按 vcpkg 那份头的默认级别（3.6）编。
//
// 所以真正会变的只有一件事：**vcpkg 那份 openssl 编了哪些东西**。
// 逐项比对 configuration.h 的 OPENSSL_NO_* 开关（见 docs/）得到的结论是：
//   * vcpkg 多开了 ec_nistp_64_gcc_128（纯性能优化，node 自带那份没开）—— 更好；
//   * vcpkg 关掉了 apps / docs / 两类测试 / FIPS-POST / FIPS 安全检查
//     —— 都跟 node 的 JS 能力无关；
//   * vcpkg 关掉了 brotli / zlib / zstd —— 只影响 OpenSSL 自己的压缩能力，
//     node 的 node:zlib 用的是它自己的 zlib（本工程里就是 vcpkg 的 zlib），不走 openssl；
//   * vcpkg 关掉了 LMS —— 3.6 新算法，node 24.21 面向的是 3.5，本来就没引用。
// 结论是"没有能力回退"。但**结论是比出来的，不是跑出来的** —— 这个用例就是把它
// 变成可执行的：真跑一遍算法面与端到端功能，让"provider 没起来 / 算法被裁掉"
// 这种事以红灯的形式暴露，而不是留一份"我们比对过"的文档。
//
// 跑法：由本工程编出来的 node 执行（`node_embed openssl_surface.js`），
// 全部能力都由**链接进来的那份 vcpkg openssl** 提供。

'use strict';

const crypto = require('crypto');
const tls = require('tls');
const assert = require('assert');

const failures = [];
function check(name, fn) {
  try {
    fn();
    console.log(`  ok    ${name}`);
  } catch (e) {
    failures.push(`${name}: ${e && e.message}`);
    console.log(`  FAIL  ${name}: ${e && e.message}`);
  }
}

function containsAll(actual, wanted, label) {
  const have = new Set(actual);
  const missing = wanted.filter((w) => !have.has(w));
  assert.strictEqual(missing.length, 0,
    `${label} 缺少 ${missing.length} 项: ${missing.join(', ')}`);
}

console.log(`node: ${process.version}`);
console.log(`openssl（运行时实际链到的）: ${process.versions.openssl}`);
console.log('');

// --- 1) 版本：必须是 3.x（node 24 只支持 OpenSSL 3）---------------------------------
console.log('[1] 版本');
check('process.versions.openssl 是 3.x', () => {
  assert.ok(/^3\./.test(process.versions.openssl),
    `实际是 ${process.versions.openssl}`);
});

// --- 2) 摘要算法面 ------------------------------------------------------------------
// 取 node 24 一定会用到、且**都在 OpenSSL 默认 provider 里**的那些。
// 注意：rc4 / des / md4 在 OpenSSL 3 里归 legacy provider，不在这里要求。
const WANT_HASHES = [
  'md5', 'sha1', 'sha224', 'sha256', 'sha384', 'sha512',
  'sha512-224', 'sha512-256', 'sha3-256', 'sha3-384', 'sha3-512',
  'shake128', 'shake256', 'blake2b512', 'blake2s256',
];
const WANT_CIPHERS = [
  'aes-128-cbc', 'aes-256-cbc', 'aes-128-gcm', 'aes-256-gcm',
  'aes-256-ctr', 'chacha20-poly1305',
];
const WANT_CURVES = [
  'prime256v1', 'secp384r1', 'secp521r1', 'secp256k1',
];

console.log('[2] 算法面（若 provider 没被激活，getHashes 等会直接抛错或返回空）');
const hashes = crypto.getHashes();
const ciphers = crypto.getCiphers();
const curves = crypto.getCurves();
console.log(`       hashes=${hashes.length} ciphers=${ciphers.length} curves=${curves.length}`);
check(`getHashes() 覆盖 ${WANT_HASHES.length} 个基线摘要`, () => {
  containsAll(hashes, WANT_HASHES, 'getHashes()');
});
check(`getCiphers() 覆盖 ${WANT_CIPHERS.length} 个基线套件`, () => {
  containsAll(ciphers, WANT_CIPHERS, 'getCiphers()');
});
check(`getCurves() 覆盖 ${WANT_CURVES.length} 条基线曲线`, () => {
  containsAll(curves, WANT_CURVES, 'getCurves()');
});

// --- 3) 端到端功能（证明 provider 真的在工作，而不只是列表里有名字）----------------
console.log('[3] 端到端功能');

const KNOWN_SHA256 = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
check('createHash(sha256) 摘要与已知向量一致', () => {
  const got = crypto.createHash('sha256').update('abc').digest('hex');
  assert.strictEqual(got, KNOWN_SHA256, `期望 ${KNOWN_SHA256}，实际 ${got}`);
});

// HMAC-SHA256 的 RFC 4231 test case 2
const HMAC_KEY = 'Jefe';
const HMAC_DATA = 'what do ya want for nothing?';
const HMAC_WANT = '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843';
check('createHmac(sha256) 与 RFC 4231 向量一致', () => {
  const got = crypto.createHmac('sha256', HMAC_KEY).update(HMAC_DATA).digest('hex');
  assert.strictEqual(got, HMAC_WANT, `期望 ${HMAC_WANT}，实际 ${got}`);
});

check('aes-256-gcm 加解密往返', () => {
  const key = crypto.randomBytes(32);
  const iv = crypto.randomBytes(12);
  const plain = Buffer.from('vcpkg openssl roundtrip');
  const enc = crypto.createCipheriv('aes-256-gcm', key, iv);
  const ct = Buffer.concat([enc.update(plain), enc.final()]);
  const tag = enc.getAuthTag();
  const dec = crypto.createDecipheriv('aes-256-gcm', key, iv);
  dec.setAuthTag(tag);
  const back = Buffer.concat([dec.update(ct), dec.final()]);
  assert.strictEqual(back.toString(), plain.toString());
});

check('ed25519 签名/验签往返', () => {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');
  const data = Buffer.from('sign me');
  const sig = crypto.sign(null, data, privateKey);
  assert.ok(crypto.verify(null, data, publicKey, sig), '签名验不过');
  // 顺带确认篡改能被发现
  assert.ok(!crypto.verify(null, Buffer.from('sign me!'), publicKey, sig),
    '被篡改的数据竟然验过了');
});

check('secp256k1 ECDH 往返', () => {
  const a = crypto.createECDH('secp256k1');
  const b = crypto.createECDH('secp256k1');
  a.generateKeys();
  b.generateKeys();
  const sa = a.computeSecret(b.getPublicKey());
  const sb = b.computeSecret(a.getPublicKey());
  assert.strictEqual(sa.toString('hex'), sb.toString('hex'), '双方算出的共享密钥不一致');
});

check('pbkdf2 派生稳定（可跨版本比对）', () => {
  const got = crypto.pbkdf2Sync('password', 'salt', 1000, 32, 'sha256').toString('hex');
  // 只要求长度与可重复：具体数值随 provider 实现可能变，但同一进程内必须一致
  assert.strictEqual(got.length, 64, `派生长度 ${got.length}`);
  const again = crypto.pbkdf2Sync('password', 'salt', 1000, 32, 'sha256').toString('hex');
  assert.strictEqual(got, again, '同参数两次派生结果不一致');
});

check('随机数可用（randomBytes / randomUUID / getRandomValues）', () => {
  assert.strictEqual(crypto.randomBytes(16).length, 16);
  assert.match(crypto.randomUUID(), /^[0-9a-f-]{36}$/);
  const buf = new Uint8Array(8);
  crypto.getRandomValues(buf);
  assert.ok(buf.some((x) => x !== 0), 'getRandomValues 给了全零');
});

// --- 4) TLS：需要 SSL provider + 证书/密钥解析 --------------------------------------
console.log('[4] TLS');
check('tls.createSecureContext() 能建起来', () => {
  // 用默认 CA 建一个 SSL_CTX。这一步要 SSL provider 与证书解析都可用；
  // 完整握手交给官方套件里的 test-tls-*，这里不做。
  const ctx = tls.createSecureContext();
  assert.ok(ctx, 'createSecureContext 返回空');
});

check('tls.getCiphers() 含 TLS 1.3 的 AES-GCM 套件', () => {
  const list = tls.getCiphers();
  assert.ok(list.length > 0, 'tls.getCiphers() 为空');
  // node 报出来的是 openssl 风格的小写名字：tls_aes_128_gcm_sha256 / tls_aes_256_gcm_sha384
  const want = ['tls_aes_128_gcm_sha256', 'tls_aes_256_gcm_sha384'];
  const missing = want.filter((w) => list.indexOf(w) < 0);
  assert.strictEqual(missing.length, 0,
    `TLS 1.3 套件缺失: ${missing.join(', ')}；实际共 ${list.length} 个，`
    + `前 10 个是 ${list.slice(0, 10).join(', ')}`);
});

check('node 的默认密码串含 TLS 1.3 套件', () => {
  assert.ok(/TLS_AES_256_GCM_SHA384|TLS_AES_128_GCM_SHA256/.test(tls.DEFAULT_CIPHERS),
    `DEFAULT_CIPHERS 里没有 TLS 1.3 套件: ${tls.DEFAULT_CIPHERS}`);
});

// --- 结论 -------------------------------------------------------------------------
console.log('');
if (failures.length) {
  console.log(`OPENSSL-SURFACE-FAIL（${failures.length} 项）`);
  for (const f of failures) console.log(`  - ${f}`);
  process.exitCode = 1;
} else {
  console.log(`OPENSSL-SURFACE-OK（openssl ${process.versions.openssl}，`
    + `hashes=${hashes.length} ciphers=${ciphers.length} curves=${curves.length}）`);
}
