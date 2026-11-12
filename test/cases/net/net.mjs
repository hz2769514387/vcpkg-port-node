// One process, several transports, each of them a different dependency in the install.
//
// An ephemeral port and 127.0.0.1 keep this self-contained: no external service, no DNS
// query for a public name, nothing a sandbox would have to allow. The interesting part is
// not that a socket connects - it is that llhttp parsed the request, nghttp2 carried the
// HTTP/2 stream, undici produced a Response, and the loop kept running for all of them.
import assert from 'node:assert/strict';
import { once } from 'node:events';
import http from 'node:http';
import http2 from 'node:http2';
import net from 'node:net';
import dns from 'node:dns';

const HOST = '127.0.0.1';

// A keep-alive client (fetch uses a global dispatcher) otherwise holds server.close()
// open until its idle timeout, which would turn a passing test into a ctest timeout.
async function closeServer(server) {
  const closed = once(server, 'close');
  server.close();
  // http2's compatibility Server is not a net.Server and has no closeAllConnections();
  // its client session is closed by the caller before this runs.
  if (typeof server.closeAllConnections === 'function') server.closeAllConnections();
  await closed;
}

async function http1() {
  const server = http.createServer((request, response) => {
    response.writeHead(200, { 'content-type': 'application/json', 'x-port': 'node' });
    response.end(JSON.stringify({ path: request.url, method: request.method }));
  });
  server.listen(0, HOST);
  await once(server, 'listening');
  try {
    const url = `http://${HOST}:${server.address().port}/orders/42`;

    // fetch() is undici: a different client implementation from http.request().
    const response = await fetch(url);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('x-port'), 'node');
    assert.deepEqual(await response.json(), { path: '/orders/42', method: 'GET' });

    // The classic client, with a POST body, so the request parser sees both directions.
    const body = await new Promise((resolve, reject) => {
      const request = http.request(url, { method: 'POST' }, (res) => {
        const parts = [];
        res.setEncoding('utf8');
        res.on('data', (chunk) => parts.push(chunk));
        res.on('end', () => resolve({ status: res.statusCode, text: parts.join('') }));
      });
      request.on('error', reject);
      request.end('payload');
    });
    assert.equal(body.status, 200);
    assert.equal(JSON.parse(body.text).path, '/orders/42');
  } finally {
    await closeServer(server);
  }
}

async function http2Stack() {
  // createServer() is the compatibility API: its request/response objects behave like
  // HTTP/1.1's, which is what an application porting an existing handler uses.
  const server = http2.createServer((request, response) => {
    response.writeHead(200, { 'content-type': 'text/plain' });
    response.end(`h2:${request.url}`);
  });
  server.listen(0, HOST);
  await once(server, 'listening');
  try {
    const client = http2.connect(`http://${HOST}:${server.address().port}`);
    try {
      const stream = client.request({ ':path': '/h2', ':method': 'GET' });
      let status = 0;
      stream.on('response', (headers) => { status = headers[':status']; });
      stream.setEncoding('utf8');
      const parts = [];
      for await (const chunk of stream) parts.push(chunk);
      assert.equal(status, 200);
      assert.equal(parts.join(''), 'h2:/h2');
    } finally {
      client.close();
    }
  } finally {
    await closeServer(server);
  }
}

async function sockets() {
  const server = net.createServer((socket) => socket.on('data', (data) => socket.write(data)));
  server.listen(0, HOST);
  await once(server, 'listening');
  try {
    const client = net.connect(server.address().port, HOST);
    await once(client, 'connect');
    client.write('ping');
    const [data] = await once(client, 'data');
    assert.equal(data.toString(), 'ping');
    client.destroy();
  } finally {
    await closeServer(server);
  }
}

async function resolution() {
  // dns.lookup goes through libuv's thread pool and the platform resolver; it is the
  // path an application uses for a hostname it was handed. 'localhost' needs no network.
  const answer = await dns.promises.lookup('localhost');
  assert.ok(answer.address, `lookup returned no address: ${JSON.stringify(answer)}`);
  assert.ok([4, 6].includes(answer.family), `unexpected family ${answer.family}`);

  // ada is behind the WHATWG URL implementation, which every HTTP client uses first.
  const url = new URL('https://example.invalid:8443/a/b?x=1&x=2#frag');
  assert.equal(url.hostname, 'example.invalid');
  assert.equal(url.port, '8443');
  assert.deepEqual(url.searchParams.getAll('x'), ['1', '2']);
  assert.equal(new URL('/relative', url).href, 'https://example.invalid:8443/relative');
}

await http1();
await http2Stack();
await sockets();
await resolution();
console.log('net: HTTP/1.1, fetch, HTTP/2, TCP, DNS and URL ok');
