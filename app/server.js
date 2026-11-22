// App de ejemplo: ALB -> EC2 (Node) -> S3. LOCATION identifica el despliegue.
//   /health               sin token (health check del ALB)
//   /ping                 JSON pequeño
//   /payload              1 MB desde memoria
//   /api/read?obj=small|large   lee un objeto de S3 (1 KB o 1 MB) y lo devuelve
//   /api/write?obj=small|large  escribe un objeto en S3 (1 KB o 1 MB)
//   ...&target=parent     usa el bucket regional (S3_PARENT_BUCKET) en lugar del bucket local
//   /upstream?n=10        n llamadas seguidas a UPSTREAM_URL/ping (BD simulada en otra ubicación)
// Las respuestas de S3 traen "Server-Timing: s3;dur=<ms>" con el tiempo gastado en S3.
const http = require('http');
const https = require('https');
const fs = require('fs');

const LOCATION = process.env.LOCATION || 'unknown';
const PORT = Number(process.env.PORT || 80);
const TLS_PORT = Number(process.env.TLS_PORT || 443);
const TOKEN = process.env.PROBE_TOKEN || '';
const UPSTREAM = process.env.UPSTREAM_URL || '';
const BUCKET = process.env.S3_BUCKET || '';
const KIND = process.env.S3_KIND || 'general'; // directory | general
const PARENT_BUCKET = process.env.S3_PARENT_BUCKET || ''; // bucket regional (solo en Bogotá)
const CERT_DIR = process.env.CERT_DIR || '/opt/app/certs';
const SIZES = { small: 1024, large: 1024 * 1024 };
const KEYS = { small: 'probe/small.bin', large: 'probe/large.bin' };
const PAYLOAD = Buffer.alloc(SIZES.large, 'x');
const agent = new http.Agent({ keepAlive: true });

let s3 = null, S3 = null;
if (BUCKET) {
  S3 = require('@aws-sdk/client-s3');
  s3 = new S3.S3Client({ region: process.env.AWS_REGION || 'us-east-1' });
}
// Mismo servicio y clase de almacenamiento en ambos lados: One Zone-IA.
const target = (url) => (url.searchParams.get('target') === 'parent' && PARENT_BUCKET) ? { bucket: PARENT_BUCKET, kind: 'general', name: 'parent' } : { bucket: BUCKET, kind: KIND, name: 'local' };
const putParams = (key, body, t = { bucket: BUCKET, kind: KIND }) => ({ Bucket: t.bucket, Key: key, Body: body, ...(t.kind === 'general' ? { StorageClass: 'ONEZONE_IA' } : {}) });
const now = () => Number(process.hrtime.bigint()) / 1e6;

async function seed() {
  for (let i = 0; i < 20; i++) {
    try {
      for (const o of ['small', 'large']) await s3.send(new S3.PutObjectCommand(putParams(KEYS[o], PAYLOAD.subarray(0, SIZES[o]))));
      console.log('S3 listo:', BUCKET); return;
    } catch (e) { console.log('seed reintento:', e.message); await new Promise(r => setTimeout(r, 5000)); }
  }
}
if (s3) seed();

function upstreamPing() {
  return new Promise((resolve, reject) => {
    const t0 = now();
    const req = http.get(UPSTREAM + '/ping', { agent, headers: { 'x-probe-token': TOKEN } }, (r) => { r.resume(); r.on('end', () => resolve(now() - t0)); });
    req.on('error', reject);
    req.setTimeout(5000, () => req.destroy(new Error('timeout')));
  });
}

async function handler(req, res) {
  const url = new URL(req.url, 'http://x');
  const h = { 'x-location': LOCATION, 'cache-control': 'no-store' };
  if (url.pathname === '/health') { res.writeHead(200, h); return res.end('ok'); }
  if (TOKEN && req.headers['x-probe-token'] !== TOKEN) { res.writeHead(403); return res.end(); }

  if (url.pathname === '/ping') {
    res.writeHead(200, { ...h, 'content-type': 'application/json' });
    return res.end(JSON.stringify({ ok: true, location: LOCATION, ts: Date.now() }));
  }
  if (url.pathname === '/payload') {
    res.writeHead(200, { ...h, 'content-type': 'application/octet-stream', 'content-length': PAYLOAD.length });
    return res.end(PAYLOAD);
  }
  if ((url.pathname === '/api/read' || url.pathname === '/api/write') && s3) {
    const obj = url.searchParams.get('obj') === 'large' ? 'large' : 'small';
    const t = target(url);
    try {
      const t0 = now();
      if (url.pathname === '/api/read') {
        const out = await s3.send(new S3.GetObjectCommand({ Bucket: t.bucket, Key: KEYS[obj] }));
        const body = Buffer.from(await out.Body.transformToByteArray());
        const ms = (now() - t0).toFixed(1);
        res.writeHead(200, { ...h, 'content-type': 'application/octet-stream', 'content-length': body.length, 'server-timing': `s3;dur=${ms}`, 'x-s3-target': t.name });
        return res.end(body);
      }
      await s3.send(new S3.PutObjectCommand(putParams(KEYS[obj], PAYLOAD.subarray(0, SIZES[obj]), t)));
      const ms = (now() - t0).toFixed(1);
      res.writeHead(200, { ...h, 'content-type': 'application/json', 'server-timing': `s3;dur=${ms}`, 'x-s3-target': t.name });
      return res.end(JSON.stringify({ ok: true, bucket_kind: t.kind, target: t.name, obj, bytes: SIZES[obj], s3_ms: Number(ms) }));
    } catch (e) { res.writeHead(502); return res.end(JSON.stringify({ error: String(e.message || e) })); }
  }
  if (url.pathname === '/upstream' && UPSTREAM) {
    const n = Math.min(Math.max(parseInt(url.searchParams.get('n') || '10', 10) || 10, 1), 50);
    try {
      const t0 = now();
      for (let i = 0; i < n; i++) await upstreamPing();
      const total = now() - t0, r2 = (x) => Math.round(x * 100) / 100;
      res.writeHead(200, { ...h, 'content-type': 'application/json' });
      return res.end(JSON.stringify({ location: LOCATION, queries: n, total_ms: r2(total), per_query_ms: r2(total / n) }));
    } catch (e) { res.writeHead(502); return res.end(JSON.stringify({ error: String(e.message || e) })); }
  }
  res.writeHead(404); res.end();
}

http.createServer(handler).listen(PORT, () => console.log(`http ${PORT} (${LOCATION})`));
try {
  const opts = { key: fs.readFileSync(`${CERT_DIR}/key.pem`), cert: fs.readFileSync(`${CERT_DIR}/cert.pem`) };
  https.createServer(opts, handler).listen(TLS_PORT, () => console.log(`https ${TLS_PORT} (${LOCATION})`));
} catch (e) { console.log('sin TLS:', e.message); }
