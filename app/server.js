// API mínima sin dependencias. LOCATION identifica el despliegue.
//   /ping            JSON pequeño, sin caché
//   /payload         1 MB, sin caché
//   /cached          JSON pequeño, cacheable (para CloudFront)
//   /cached-payload  1 MB, cacheable (para CloudFront)
//   /upstream?n=10   hace n llamadas secuenciales a UPSTREAM_URL/ping y mide el tiempo
//                    (simula una app que consulta una base de datos en otra ubicación)
const http = require('http');
const https = require('https');
const fs = require('fs');

const LOCATION = process.env.LOCATION || 'unknown';
const PORT = Number(process.env.PORT || 80);
const TLS_PORT = Number(process.env.TLS_PORT || 443);
const TOKEN = process.env.PROBE_TOKEN || '';
const UPSTREAM = process.env.UPSTREAM_URL || '';
const CERT_DIR = process.env.CERT_DIR || '/opt/app/certs';
const PAYLOAD = Buffer.alloc(1024 * 1024, 'x'); // 1 MB
const agent = new http.Agent({ keepAlive: true }); // conexión reutilizada, como un pool de BD

function upstreamPing() {
  return new Promise((resolve, reject) => {
    const t0 = process.hrtime.bigint();
    const req = http.get(UPSTREAM + '/ping', { agent, headers: { 'x-probe-token': TOKEN } }, (r) => {
      r.resume();
      r.on('end', () => resolve(Number(process.hrtime.bigint() - t0) / 1e6));
    });
    req.on('error', reject);
    req.setTimeout(5000, () => req.destroy(new Error('timeout')));
  });
}

async function handler(req, res) {
  if (TOKEN && req.headers['x-probe-token'] !== TOKEN) { res.writeHead(403); return res.end(); }
  const url = new URL(req.url, 'http://x');
  const base = { 'x-location': LOCATION };
  const nocache = { 'cache-control': 'no-store' };
  const cache = { 'cache-control': 'public, max-age=3600' };

  if (url.pathname === '/ping' || url.pathname === '/cached') {
    res.writeHead(200, { ...base, ...(url.pathname === '/cached' ? cache : nocache), 'content-type': 'application/json' });
    return res.end(JSON.stringify({ ok: true, location: LOCATION, ts: Date.now() }));
  }
  if (url.pathname === '/payload' || url.pathname === '/cached-payload') {
    res.writeHead(200, { ...base, ...(url.pathname === '/cached-payload' ? cache : nocache), 'content-type': 'application/octet-stream', 'content-length': PAYLOAD.length });
    return res.end(PAYLOAD);
  }
  if (url.pathname === '/upstream' && UPSTREAM) {
    const n = Math.min(Math.max(parseInt(url.searchParams.get('n') || '10', 10) || 10, 1), 50);
    try {
      const t0 = process.hrtime.bigint();
      for (let i = 0; i < n; i++) await upstreamPing();
      const total = Number(process.hrtime.bigint() - t0) / 1e6;
      const r2 = (x) => Math.round(x * 100) / 100;
      res.writeHead(200, { ...base, ...nocache, 'content-type': 'application/json' });
      return res.end(JSON.stringify({ location: LOCATION, queries: n, total_ms: r2(total), per_query_ms: r2(total / n) }));
    } catch (e) {
      res.writeHead(502); return res.end(JSON.stringify({ error: String(e.message || e) }));
    }
  }
  res.writeHead(404); res.end();
}

http.createServer(handler).listen(PORT, () => console.log(`http ${PORT} (${LOCATION})`));
try {
  const opts = { key: fs.readFileSync(`${CERT_DIR}/key.pem`), cert: fs.readFileSync(`${CERT_DIR}/cert.pem`) };
  https.createServer(opts, handler).listen(TLS_PORT, () => console.log(`https ${TLS_PORT} (${LOCATION})`));
} catch (e) { console.log('sin TLS:', e.message); }
