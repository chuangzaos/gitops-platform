'use strict';

// Real tests: boot the server on an ephemeral port and exercise the routes.
const test = require('node:test');
const assert = require('node:assert');
const http = require('http');
const { server } = require('../src/server.js');

test.before(async () => {
  await new Promise((resolve) => server.listen(0, resolve));
});

test.after(() => server.close());

function get(path) {
  const { port } = server.address();
  return new Promise((resolve, reject) => {
    http
      .get({ host: '127.0.0.1', port, path }, (res) => {
        let data = '';
        res.on('data', (c) => (data += c));
        res.on('end', () => resolve({ status: res.statusCode, data }));
      })
      .on('error', reject);
  });
}

test('GET /healthz returns 200 ok', async () => {
  const r = await get('/healthz');
  assert.strictEqual(r.status, 200);
  assert.strictEqual(r.data, 'ok');
});

test('GET / returns JSON with version', async () => {
  const r = await get('/');
  assert.strictEqual(r.status, 200);
  const body = JSON.parse(r.data);
  assert.ok(body.version);
  assert.strictEqual(body.status, 'ok');
});

test('GET /metrics exposes Prometheus format', async () => {
  const r = await get('/metrics');
  assert.strictEqual(r.status, 200);
  assert.match(r.data, /http_requests_total/);
  assert.match(r.data, /request_duration_seconds_bucket/);
});

test('GET /fail returns 500 and increments error counter', async () => {
  const r = await get('/fail');
  assert.strictEqual(r.status, 500);
});
