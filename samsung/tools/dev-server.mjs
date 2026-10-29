// Dev server for testing the TV app in a desktop browser.
// - Serves app/ at http://localhost:8090.
// - /proxy?u=<url> forwards to YouTube with a Tizen User-Agent. A desktop browser enforces CORS; the TV's web
//   runtime doesn't for the origins in config.xml, so this stands in for that (app/js/core/net.js). Only YouTube hosts.
import { createReadStream, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, join, normalize } from 'node:path';
import { Readable } from 'node:stream';
import { fileURLToPath } from 'node:url';

const PORT = Number(process.env.PORT || 8090);
const ROOT = fileURLToPath(new URL('../app/', import.meta.url));
const TIZEN_UA =
  'Mozilla/5.0 (SMART-TV; LINUX; Tizen 8.0) AppleWebKit/537.36 (KHTML, like Gecko) 108.0.5359.1/8.0 TV Safari/537.36';
// The same hosts as the <access> list in app/config.xml.
const ALLOWED =
  /(^|\.)(youtube\.com|googlevideo\.com|ytimg\.com|ggpht\.com)$|^(suggestqueries\.google\.com|sponsor\.ajay\.app|returnyoutubedislikeapi\.com|api\.github\.com)$/;
const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.xml': 'application/xml',
  '.woff2': 'font/woff2',
};

async function proxy(req, res, target) {
  let url;
  try {
    url = new URL(target);
  } catch {
    res.writeHead(400).end('bad url');
    return;
  }
  if (url.protocol !== 'https:' || !ALLOWED.test(url.hostname)) {
    res.writeHead(403).end('host not allowed');
    return;
  }
  const headers = { 'user-agent': TIZEN_UA };
  for (const h of ['content-type', 'range', 'x-goog-visitor-id']) if (req.headers[h]) headers[h] = req.headers[h];
  const body = req.method === 'POST' ? Readable.toWeb(req) : undefined;
  try {
    const up = await fetch(url, { method: req.method, headers, body, duplex: 'half', redirect: 'follow' });
    const out = { 'access-control-allow-origin': '*' };
    for (const h of ['content-type', 'content-length', 'content-range', 'accept-ranges']) {
      const v = up.headers.get(h);
      if (v) out[h] = v;
    }
    // fetch() already decoded the body, so its length may differ from the upstream content-length.
    if (up.headers.get('content-encoding')) delete out['content-length'];
    res.writeHead(up.status, out);
    if (up.body) Readable.fromWeb(up.body).on('error', () => res.destroy()).pipe(res);
    else res.end();
    if (up.status >= 400) console.log(`proxy ${up.status} ${req.method} ${url.hostname}${url.pathname}`);
  } catch (e) {
    console.log(`proxy error ${url.hostname}: ${e.message}`);
    if (!res.headersSent) res.writeHead(502);
    res.end(String(e.message));
  }
}

function serveFile(req, res, pathname) {
  const rel = normalize(decodeURIComponent(pathname === '/' ? '/index.html' : pathname)).replace(/^([/\\])+/, '');
  const file = join(ROOT, rel);
  if (!file.startsWith(ROOT)) {
    res.writeHead(403).end();
    return;
  }
  try {
    const st = statSync(file);
    if (!st.isFile()) throw new Error('not a file');
    res.writeHead(200, {
      'content-type': TYPES[extname(file)] || 'application/octet-stream',
      'content-length': st.size,
      'cache-control': 'no-store',
    });
    createReadStream(file).pipe(res);
  } catch {
    res.writeHead(404).end('not found');
  }
}

createServer((req, res) => {
  const u = new URL(req.url, `http://localhost:${PORT}`);
  if (u.pathname === '/proxy') proxy(req, res, u.searchParams.get('u'));
  else serveFile(req, res, u.pathname);
}).listen(PORT, () => console.log(`YouPipe TV dev server: http://localhost:${PORT}`));
