const client = require('prom-client');

const register = new client.Registry();
register.setDefaultLabels({ app: 'pulse-api' });

// Node.js 預設指標：CPU、記憶體、event loop lag、GC 等
client.collectDefaultMetrics({ register });

const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request duration in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
  registers: [register],
});

// Express middleware：記錄每個 request 的延遲
function metricsMiddleware(req, res, next) {
  if (req.path === '/metrics') return next();
  const end = httpRequestDuration.startTimer();
  res.on('finish', () => {
    const route = req.route ? req.baseUrl + req.route.path : 'unmatched';
    end({ method: req.method, route, status_code: res.statusCode });
  });
  next();
}

module.exports = { register, metricsMiddleware };
