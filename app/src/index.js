const { createApp } = require('./app');

const PORT = Number(process.env.PORT) || 3000;
const SHUTDOWN_DELAY_MS = Number(process.env.SHUTDOWN_DELAY_MS) || 5000;

const state = { ready: true };
const app = createApp(state);

const server = app.listen(PORT, () => {
  console.log(`pulse-api listening on :${PORT}`);
});

// Graceful shutdown：先標記 not ready，等 Service 移除此 Pod 後再關閉
function shutdown(signal) {
  console.log(`${signal} received, shutting down...`);
  state.ready = false;
  setTimeout(() => {
    server.close(() => {
      console.log('server closed');
      process.exit(0);
    });
  }, SHUTDOWN_DELAY_MS);
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
