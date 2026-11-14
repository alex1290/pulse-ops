const express = require('express');
const os = require('os');
const { register, metricsMiddleware } = require('./metrics');

const VERSION = process.env.APP_VERSION || 'dev';

function createApp(state = { ready: true }) {
  const app = express();
  app.disable('x-powered-by');
  app.use(express.json());
  app.use(metricsMiddleware);

  // Liveness：process 還活著就回 200（K8s livenessProbe）
  app.get('/health', (req, res) => {
    res.json({ status: 'ok', uptime: process.uptime() });
  });

  // Readiness：可以接流量才回 200（K8s readinessProbe）
  // 收到 SIGTERM 時會先變成 503，讓 Service 停止導流再關閉
  app.get('/ready', (req, res) => {
    if (!state.ready) return res.status(503).json({ status: 'not ready' });
    res.json({ status: 'ready' });
  });

  // Prometheus 抓取的端點
  app.get('/metrics', async (req, res) => {
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
  });

  app.get('/', (req, res) => {
    res.json({ name: 'pulse-api', version: VERSION, hostname: os.hostname() });
  });

  app.get('/api/hello', (req, res) => {
    const name = req.query.name || 'DevOps';
    res.json({ message: `Hello, ${name}!` });
  });

  // 範例：模擬慢請求，可用來觀察 Grafana 上的延遲變化
  app.get('/api/slow', async (req, res) => {
    const ms = Math.min(Number(req.query.ms) || 500, 5000);
    await new Promise((r) => setTimeout(r, ms));
    res.json({ delayed: ms });
  });

  app.use((req, res) => res.status(404).json({ error: 'not found' }));

  return app;
}

module.exports = { createApp };
