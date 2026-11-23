'use strict';

// Built-in, trusted OpenChamber service. It appends the session events the host
// posts to the extension's private data directory; no host secret is inherited.
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');

const port = Number(process.env.OPENCHAMBER_SERVICE_PORT || 0);
const token = process.env.OPENCHAMBER_SERVICE_TOKEN || '';
const dataDir = process.env.OPENCHAMBER_SERVICE_DATA_DIR || '';
const maxBody = 1024 * 1024;

if (!port || !token || !dataDir) {
  process.stderr.write('fleet-session-journal: missing service environment\n');
  process.exit(1);
}

const journal = path.join(dataDir, 'events.jsonl');
fs.mkdirSync(dataDir, { recursive: true, mode: 0o700 });

function reply(response, status, body) {
  response.writeHead(status, { 'content-type': 'application/json' });
  response.end(JSON.stringify(body));
}

const server = http.createServer((request, response) => {
  if (request.headers.authorization !== `Bearer ${token}`) {
    return reply(response, 401, { ok: false });
  }
  if (request.method === 'GET' && request.url === '/health') {
    return reply(response, 200, { ok: true });
  }
  if (request.method !== 'POST' || request.url !== '/session-events') {
    return reply(response, 404, { ok: false });
  }

  let body = '';
  request.setEncoding('utf8');
  request.on('data', (chunk) => {
    body += chunk;
    if (body.length > maxBody) request.destroy();
  });
  request.on('end', () => {
    try {
      const event = JSON.parse(body);
      fs.appendFileSync(journal, `${JSON.stringify(event)}\n`, { mode: 0o600 });
      reply(response, 200, { ok: true });
    } catch {
      reply(response, 400, { ok: false });
    }
  });
});

server.listen(port, '127.0.0.1');
