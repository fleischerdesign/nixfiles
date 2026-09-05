import { Service, type Context } from '@deepseek-ai/cordis';
import * as http from 'node:http';
import * as net from 'node:net';
import * as crypto from 'node:crypto';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { SlidingWindowDebouncer } from './debouncer.js';
import type { CloudEvent, IngressPluginConfig } from './types.js';

export const name = 'ingress';
export const inject = [];

declare module '@deepseek-ai/cordis' {
  interface Context {
    ingress: IngressGatewayService;
  }
}

export class IngressGatewayService extends Service {
  private debouncer: SlidingWindowDebouncer;
  private httpServer?: http.Server;
  private socketServer?: net.Server;

  constructor(ctx: Context, private config: IngressPluginConfig) {
    super(ctx, 'ingress');

    const windowMs = config.debouncing?.windowMs ?? 15000;
    this.debouncer = new SlidingWindowDebouncer(windowMs, (event) => {
      this.dispatchCloudEvent(event);
    });

    if (config.http?.enabled) {
      this.startHttpServer(config.http);
    }

    if (config.socket?.enabled && config.socket?.path) {
      this.startSocketServer(config.socket.path);
    }
  }

  /**
   * Dispatch consolidated CloudEvent to Cordis event bus.
   */
  dispatchCloudEvent(event: CloudEvent): void {
    // Emit strongly-typed CloudEvent on the cordis context
    this.ctx.emit('ingress/event' as any, event);
  }

  /**
   * HTTP Webhook Server with HMAC-SHA256 verification.
   */
  private startHttpServer(cfg: NonNullable<IngressPluginConfig['http']>): void {
    const port = cfg.port ?? 3890;
    const host = cfg.host ?? '127.0.0.1';

    this.httpServer = http.createServer(async (req, res) => {
      if (req.method !== 'POST') {
        res.writeHead(405, { 'Content-Type': 'text/plain' });
        res.end('Method Not Allowed');
        return;
      }

      let body = '';
      req.on('data', (chunk) => { body += chunk; });
      req.on('end', () => {
        // HMAC Signature Check if secret is configured
        if (cfg.secret) {
          const signature = req.headers['x-hub-signature-256'] || req.headers['x-signature-256'];
          if (typeof signature !== 'string') {
            res.writeHead(401, { 'Content-Type': 'text/plain' });
            res.end('Missing HMAC Signature');
            return;
          }

          const hmac = crypto.createHmac('sha256', cfg.secret);
          hmac.update(body);
          const expected = `sha256=${hmac.digest('hex')}`;

          if (!crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) {
            res.writeHead(403, { 'Content-Type': 'text/plain' });
            res.end('Invalid HMAC Signature');
            return;
          }
        }

        try {
          const raw = JSON.parse(body);
          const cloudEvent: CloudEvent = {
            specversion: '1.0',
            id: raw.id || crypto.randomUUID(),
            source: raw.source || req.headers['x-event-source'] as string || 'urn:dsh:webhook',
            type: raw.type || req.headers['x-event-type'] as string || 'generic.webhook',
            time: raw.time || new Date().toISOString(),
            data: raw.data || raw
          };

          this.debouncer.ingest(cloudEvent);

          res.writeHead(202, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ status: 'accepted', id: cloudEvent.id }));
        } catch {
          res.writeHead(400, { 'Content-Type': 'text/plain' });
          res.end('Invalid JSON payload');
        }
      });
    });

    this.httpServer.listen(port, host);
  }

  /**
   * Unix Domain Socket Server for local system events.
   */
  private startSocketServer(socketPath: string): void {
    const dir = path.dirname(socketPath);
    if (!fs.existsSync(dir)) {
      try { fs.mkdirSync(dir, { recursive: true }); } catch {}
    }
    if (fs.existsSync(socketPath)) {
      try { fs.unlinkSync(socketPath); } catch {}
    }

    this.socketServer = net.createServer((conn) => {
      let buffer = '';
      conn.on('data', (chunk) => {
        buffer += chunk.toString();
        const lines = buffer.split('\n');
        buffer = lines.pop() ?? '';

        for (const line of lines) {
          if (!line.trim()) continue;
          try {
            const raw = JSON.parse(line);
            const cloudEvent: CloudEvent = {
              specversion: '1.0',
              id: raw.id || crypto.randomUUID(),
              source: raw.source || 'urn:dsh:local-socket',
              type: raw.type || 'system.event',
              time: raw.time || new Date().toISOString(),
              data: raw.data || raw
            };
            this.debouncer.ingest(cloudEvent);
          } catch {}
        }
      });
    });

    this.socketServer.listen(socketPath);
  }

  close(): void {
    this.debouncer.dispose();
    this.httpServer?.close();
    this.socketServer?.close();
  }
}

export function apply(ctx: Context, config: IngressPluginConfig = {}): void {
  const service = new IngressGatewayService(ctx, config);
  ctx.provide('ingress');
  ctx.ingress = service;

  ctx.effect(() => {
    return () => {
      service.close();
    };
  });
}

export default apply;
