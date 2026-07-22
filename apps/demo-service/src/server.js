'use strict';

// Zero-dependency HTTP service that exposes:
//   GET /            -> JSON service info
//   GET /healthz     -> plain "ok" (used by probes)
//   GET /metrics     -> Prometheus text format (counter + histogram)
//   GET /fail        -> forced 500 (for alert testing)
//   GET /load?ms=N   -> artificial latency (for latency testing)
//
// No external packages required, so it builds and runs anywhere Node >= 18.

const http = require('http');

const PORT = process.env.PORT || 8080;
const VERSION = process.env.VERSION || '1.0.0';

// ---- metrics state ----
const counters = { total: 0, errors: 0 };
const BUCKETS = [0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, Infinity];
const hist = { sum: 0, counts: BUCKETS.map(() => 0) };

function observe(duration) {
  hist.sum += duration;
  for (let i = 0; i < BUCKETS.length; i++) {
    if (duration <= BUCKETS[i]) {
      hist.counts[i]++;
      break;
    }
  }
}

function renderMetrics() {
  const lines = [];
  lines.push('# HELP http_requests_total Total number of HTTP requests.');
  lines.push('# TYPE http_requests_total counter');
  lines.push(`http_requests_total ${counters.total}`);
  lines.push('# HELP http_requests_errors_total Total number of 5xx responses.');
  lines.push('# TYPE http_requests_errors_total counter');
  lines.push(`http_requests_errors_total ${counters.errors}`);
  lines.push('# HELP request_duration_seconds Request latency in seconds.');
  lines.push('# TYPE request_duration_seconds histogram');
  hist.counts.forEach((c, i) => {
    const le = BUCKETS[i] === Infinity ? '+Inf' : BUCKETS[i].toString();
    lines.push(`request_duration_seconds_bucket{le="${le}"} ${c}`);
  });
  const count = hist.counts.reduce((a, b) => a + b, 0);
  lines.push(`request_duration_seconds_sum ${hist.sum.toFixed(3)}`);
  lines.push(`request_duration_seconds_count ${count}`);
  return lines.join('\n') + '\n';
}

const server = http.createServer((req, res) => {
  const start = process.hrtime.bigint();
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  counters.total++;

  const finish = (code, body, type) => {
    const duration = Number(process.hrtime.bigint() - start) / 1e9;
    observe(duration);
    if (code >= 500) counters.errors++;
    res.writeHead(code, { 'Content-Type': type });
    res.end(body);
  };

  if (url.pathname === '/healthz') return finish(200, 'ok', 'text/plain');
  if (url.pathname === '/metrics') return finish(200, renderMetrics(), 'text/plain; version=0.0.4');
  if (url.pathname === '/') {
    return finish(200, JSON.stringify({ status: 'ok', version: VERSION, uptime: process.uptime().toFixed(1) }), 'application/json');
  }
  if (url.pathname === '/fail') return finish(500, JSON.stringify({ error: 'forced failure' }), 'application/json');
  if (url.pathname === '/load') {
    const ms = Math.min(parseInt(url.searchParams.get('ms') || '100', 10), 5000);
    return setTimeout(() => finish(200, JSON.stringify({ ok: true, sleptMs: ms }), 'application/json'), ms);
  }
  return finish(404, JSON.stringify({ error: 'not found' }), 'application/json');
});

function start() {
  server.listen(PORT, () => {
    console.log(`demo-service ${VERSION} listening on :${PORT}`);
  });
}

if (require.main === module) {
  start();
}

module.exports = { server, start };
