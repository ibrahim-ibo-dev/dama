// Local Flutter UI preview. Native release apps call the production API directly.
import http from 'node:http';
import https from 'node:https';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../build/web/', import.meta.url));
const backend = new URL(process.env.DAMA_PREVIEW_BACKEND || 'http://localhost:3000');
const port = Number(process.env.DAMA_PREVIEW_PORT || 4040);
const mime = { '.html': 'text/html', '.js': 'application/javascript', '.json': 'application/json', '.wasm': 'application/wasm', '.png': 'image/png', '.svg': 'image/svg+xml', '.ttf': 'font/ttf', '.otf': 'font/otf', '.woff2': 'font/woff2' };

http.createServer(async (request, response) => {
  try {
    const url = new URL(request.url, 'http://localhost');
    if (url.pathname.startsWith('/api/')) {
      const headers = { ...request.headers, host: backend.host };
      if (headers.origin) headers.origin = backend.origin;
      const proxy = (backend.protocol === 'https:' ? https : http).request(new URL(url.pathname + url.search, backend), {
        method: request.method, headers,
      }, upstream => {
        response.writeHead(upstream.statusCode || 502, upstream.headers);
        upstream.pipe(response);
      });
      proxy.on('error', () => { response.writeHead(502, { 'Content-Type': 'application/json' }); response.end(JSON.stringify({ error: 'Local Next.js server is unavailable.' })); });
      request.pipe(proxy);
      return;
    }
    const target = path.resolve(root, '.' + decodeURIComponent(url.pathname === '/' ? '/index.html' : url.pathname));
    if (!target.startsWith(root)) { response.writeHead(403); response.end(); return; }
    const body = await fs.readFile(target);
    response.writeHead(200, { 'Content-Type': mime[path.extname(target)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
    response.end(body);
  } catch { response.writeHead(404); response.end('Not found'); }
}).listen(port, '127.0.0.1', () => console.log(`Flutter preview: http://localhost:${port} (API proxy: ${backend.origin})`));
