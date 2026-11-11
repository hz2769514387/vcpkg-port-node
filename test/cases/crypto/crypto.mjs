// Known answers and round trips through the external OpenSSL.
//
// Nothing here tests cryptography's correctness for its own sake. Each assertion is a
// different part of libcrypto an application reaches: digests, HMAC, AEAD with its tag,
// key generation, sign/verify with KeyObjects, WebCrypto, and the cipher list a TLS
// stack enumerates. A provider that did not load fails here, not in the consumer's first
// HTTPS request.
import assert from 'node:assert/strict';
import crypto from 'node:crypto';

const { versions } = process;
assert.match(versions.openssl, /^3[.]/, `unexpected OpenSSL version ${versions.openssl}`);

// Known answers: the same input must produce the same bytes no matter which OpenSSL build
// was linked. randomBytes and randomUUID exercise the RNG, which a "digest only" build
// would leave untested.
assert.equal(crypto.createHash('sha256').update('abc').digest('hex'),
  'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
assert.equal(crypto.createHash('sha512').update('abc').digest('hex').length, 128);
assert.equal(crypto.createHmac('sha256', 'key').update('abc').digest('hex'),
  '9c196e32dc0175f86f4b1cb89289d6619de6bee699e4c378e68309ed97a1a6ab');
assert.equal(crypto.randomBytes(32).length, 32);
assert.match(crypto.randomUUID(), /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/);

// AEAD: the authentication tag has to round trip. An engine that encrypts but does not
// carry the tag state still produces ciphertext, so both halves are checked.
assert.ok(crypto.getCiphers().includes('aes-256-gcm'));
const iv = crypto.randomBytes(12);
const sessionKey = crypto.randomBytes(32);
const payload = Buffer.from('payload-text-for-aead', 'utf8');
const cipher = crypto.createCipheriv('aes-256-gcm', sessionKey, iv);
const ciphertext = Buffer.concat([cipher.update(payload), cipher.final()]);
const authTag = cipher.getAuthTag();
const decipher = crypto.createDecipheriv('aes-256-gcm', sessionKey, iv);
decipher.setAuthTag(authTag);
assert.equal(Buffer.concat([decipher.update(ciphertext), decipher.final()]).toString(), payload.toString());
assert.throws(() => {
  const broken = crypto.createDecipheriv('aes-256-gcm', sessionKey, iv);
  broken.setAuthTag(Buffer.alloc(16));
  broken.final();
});

// KeyObjects and sign/verify: the shape the TLS and JWT code in a product uses.
const pair = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const message = Buffer.from('signed-by-the-consumer');
const signature = crypto.sign('sha256', message, pair.privateKey);
assert.equal(crypto.verify('sha256', message, pair.publicKey, signature), true);
assert.equal(crypto.verify('sha256', Buffer.from('tampered'), pair.publicKey, signature), false);
assert.ok(pair.publicKey.export({ type: 'spki', format: 'pem' }).startsWith('-----BEGIN PUBLIC KEY-----'));

// WebCrypto is a separate entry point into the same library.
const digest = await crypto.subtle.digest('SHA-256', Buffer.from('a'));
assert.equal(Buffer.from(digest).toString('hex'),
  'ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb');

console.log(`crypto: application paths ok (OpenSSL ${versions.openssl})`);
