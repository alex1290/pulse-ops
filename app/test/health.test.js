const { test, before, after } = require('node:test');
const assert = require('node:assert');
const { createApp } = require('../src/app');

const state = { ready: true };
let server;
let base;

before(async () => {
  server = createApp(state).listen(0);
  await new Promise((r) => server.once('listening', r));
  base = `http://127.0.0.1:${server.address().port}`;
});

after(() => server.close());

test('GET /health returns ok', async () => {
  const res = await fetch(`${base}/health`);
  assert.strictEqual(res.status, 200);
  assert.strictEqual((await res.json()).status, 'ok');
});

test('GET /ready reflects readiness state', async () => {
  assert.strictEqual((await fetch(`${base}/ready`)).status, 200);
  state.ready = false;
  assert.strictEqual((await fetch(`${base}/ready`)).status, 503);
  state.ready = true;
});

test('GET /metrics exposes Prometheus metrics', async () => {
  await fetch(`${base}/api/hello`);
  const body = await (await fetch(`${base}/metrics`)).text();
  assert.match(body, /http_request_duration_seconds_bucket/);
  assert.match(body, /process_cpu_user_seconds_total/);
});

test('unknown route returns 404', async () => {
  assert.strictEqual((await fetch(`${base}/nope`)).status, 404);
});
