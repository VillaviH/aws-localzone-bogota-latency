// API mínima sin dependencias. LOCATION identifica el despliegue.
const http = require('http');
const LOCATION = process.env.LOCATION || 'unknown';
const PORT = Number(process.env.PORT || 80);
const TOKEN = process.env.PROBE_TOKEN || '';
const PAYLOAD = Buffer.alloc(1024 * 1024, 'x'); // 1 MB

http.createServer((req, res) => {
  if (TOKEN && req.headers['x-probe-token'] !== TOKEN) { res.writeHead(403); return res.end(); }
  const path = req.url.split('?')[0];
  if (path === '/ping') {
    res.writeHead(200, { 'content-type': 'application/json', 'cache-control': 'no-store', 'x-location': LOCATION });
    return res.end(JSON.stringify({ ok: true, location: LOCATION, ts: Date.now() }));
  }
  if (path === '/payload') {
    res.writeHead(200, { 'content-type': 'application/octet-stream', 'cache-control': 'no-store', 'x-location': LOCATION, 'content-length': PAYLOAD.length });
    return res.end(PAYLOAD);
  }
  res.writeHead(404).end();
}).listen(PORT, () => console.log(`listening ${PORT} (${LOCATION})`));
