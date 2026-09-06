import { Service, type Context } from '@deepseek-ai/cordis';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { SessionShareEngine } from './engine.js';
import type { ShareOptions } from './types.js';

export const name = 'share';
export const inject = ['webServer', 'auth'];

declare module '@deepseek-ai/cordis' {
  interface Context {
    share: SessionShareService;
    auth: any;
    webServer: any;
  }
}

export class SessionShareService extends Service {
  public engine: SessionShareEngine;

  constructor(ctx: Context) {
    super(ctx, 'share');
    this.engine = new SessionShareEngine();

    this.registerApiRoutes();
  }

  private registerApiRoutes(): void {
    const webServer = this.ctx.webServer;
    if (!webServer) return;

    // Route 1: POST /api/share/create
    webServer.register({
      kind: 'exact',
      path: '/api/share/create',
      handler: async (req: IncomingMessage, res: ServerResponse) => {
        if (req.method !== 'POST') {
          res.writeHead(405, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'Method Not Allowed' }));
          return;
        }

        const caller = (req as any).tenant || { username: 'local', clearance: 'Admin', groups: ['wheel'] };

        try {
          const body = await this.readJsonBody(req);
          const { sessionId, title, scope, accessMode, permission, stripSecrets, ttlSeconds, messages } = body;

          if (!sessionId) {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: 'Missing required field: sessionId' }));
            return;
          }

          const shareOpts: ShareOptions = {
            sessionId,
            scope: scope || 'public',
            accessMode: accessMode || 'snapshot',
            permission: permission || 'view',
            stripSecrets: stripSecrets !== false,
            ttlSeconds: ttlSeconds ? Number(ttlSeconds) : 0,
          };

          const result = await this.engine.createShare(
            shareOpts,
            caller.username,
            title || 'Shared Session',
            Array.isArray(messages) ? messages : []
          );

          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify(result));
        } catch (err: any) {
          res.writeHead(500, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: err.message || 'Internal Server Error' }));
        }
      },
    });

    // Route 2: GET /api/share/:token
    webServer.register({
      kind: 'prefix',
      path: '/api/share/view',
      handler: async (req: IncomingMessage, res: ServerResponse) => {
        const url = new URL(req.url || '/', 'http://127.0.0.1');
        const token = url.searchParams.get('token');

        if (!token) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'Missing token query parameter' }));
          return;
        }

        const caller = (req as any).tenant;
        const share = this.engine.getShareByToken(token, caller);

        if (!share) {
          res.writeHead(404, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'Share link expired, revoked, or unauthorized.' }));
          return;
        }

        // Anti-crawler security headers
        res.writeHead(200, {
          'Content-Type': 'application/json',
          'X-Robots-Tag': 'noindex, nofollow, noarchive, nosnippet',
          'Cache-Control': 'private, no-cache, no-store, must-revalidate',
        });
        res.end(JSON.stringify(share));
      },
    });

    // Route 3: GET /api/share/list?sessionId=...
    webServer.register({
      kind: 'prefix',
      path: '/api/share/list',
      handler: async (req: IncomingMessage, res: ServerResponse) => {
        const url = new URL(req.url || '/', 'http://127.0.0.1');
        const sessionId = url.searchParams.get('sessionId');

        if (!sessionId) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'Missing sessionId query parameter' }));
          return;
        }

        const list = this.engine.listSessionShares(sessionId);
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(list));
      },
    });

    // Route 4: POST /api/share/revoke
    webServer.register({
      kind: 'exact',
      path: '/api/share/revoke',
      handler: async (req: IncomingMessage, res: ServerResponse) => {
        if (req.method !== 'POST') {
          res.writeHead(405, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'Method Not Allowed' }));
          return;
        }

        try {
          const body = await this.readJsonBody(req);
          const { shareId } = body;

          if (!shareId) {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: 'Missing shareId' }));
            return;
          }

          const success = this.engine.revokeShare(shareId);
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ success }));
        } catch (err: any) {
          res.writeHead(500, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: err.message }));
        }
      },
    });

    // Route 5: POST /api/share/acl
    webServer.register({
      kind: 'exact',
      path: '/api/share/acl',
      handler: async (req: IncomingMessage, res: ServerResponse) => {
        if (req.method !== 'POST') {
          res.writeHead(405, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'Method Not Allowed' }));
          return;
        }

        try {
          const body = await this.readJsonBody(req);
          const { sessionId, grantee, permission, action } = body;

          if (!sessionId || !grantee) {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: 'Missing sessionId or grantee' }));
            return;
          }

          if (action === 'revoke') {
            this.engine.revokeAcl(sessionId, grantee);
          } else {
            this.engine.grantAcl(sessionId, grantee, permission || 'view');
          }

          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ success: true }));
        } catch (err: any) {
          res.writeHead(500, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: err.message }));
        }
      },
    });
  }

  private readJsonBody(req: IncomingMessage): Promise<any> {
    return new Promise((resolve, reject) => {
      let data = '';
      req.on('data', (chunk) => {
        data += chunk;
        if (data.length > 5 * 1024 * 1024) {
          // 5MB safety limit
          reject(new Error('Payload Too Large'));
        }
      });
      req.on('end', () => {
        try {
          resolve(data ? JSON.parse(data) : {});
        } catch (e) {
          reject(new Error('Invalid JSON'));
        }
      });
      req.on('error', reject);
    });
  }
}

export function apply(ctx: Context): void {
  new SessionShareService(ctx);
}
