import { Service, type Context } from '@deepseek-ai/cordis';
import * as crypto from 'node:crypto';
import * as fs from 'node:fs';
import * as yaml from 'js-yaml';
import type { IncomingMessage, ServerResponse } from 'node:http';
import type { AuthPluginConfig, UserIdentity } from './types.js';
import {
  ForwardProxyStrategy,
  LoopbackStrategy,
  PeerMeshStrategy,
  type AuthStrategy
} from './strategy.js';

export const name = 'auth';
export const inject = ['webServer'];

declare module '@deepseek-ai/cordis' {
  interface Context {
    auth: IdentityAuthGatewayService;
    tenant?: UserIdentity;
    webServer: any;
  }
}

export class IdentityAuthGatewayService extends Service {
  private strategies: AuthStrategy[] = [];
  private signingSecret: Buffer;

  constructor(ctx: Context, private config: AuthPluginConfig) {
    super(ctx, 'auth');

    // Initialize strategies based on priority
    this.strategies.push(new PeerMeshStrategy(this.config));
    this.strategies.push(new ForwardProxyStrategy(this.config));
    this.strategies.push(new LoopbackStrategy(this.config));

    // Load or generate durable cookie signing secret
    this.signingSecret = this.resolveSigningSecret();

    // Intercept web requests to ensure seamless authentication and cookie minting
    this.interceptWebServer();
  }

  private resolveSigningSecret(): Buffer {
    // Check if credentials.yaml has client-connection/browser-session secret
    const credPath = `${process.env.DSH_HOME || process.env.HOME + '/.dsh'}/.credentials.yaml`;
    try {
      if (fs.existsSync(credPath)) {
        const doc: any = yaml.load(fs.readFileSync(credPath, 'utf8'));
        const secStr = doc?.records?.['client-connection/browser-session']?.payload?.secret;
        if (secStr) {
          const padding = '='.repeat((4 - secStr.length % 4) % 4);
          return Buffer.from(secStr.replaceAll('-', '+').replaceAll('_', '/') + padding, 'base64');
        }
      }
    } catch {
      // Fall through to generated secret
    }
    return crypto.randomBytes(32);
  }

  async authenticateRequest(req: IncomingMessage): Promise<UserIdentity | null> {
    const remoteIp = req.socket.remoteAddress?.replace(/^.*:/, '') || '127.0.0.1';

    for (const strategy of this.strategies) {
      if (strategy.canHandle(req, remoteIp)) {
        const identity = await strategy.authenticate(req, remoteIp);
        if (identity) return identity;
      }
    }
    return null;
  }

  private interceptWebServer(): void {
    // Wrap webServer route dispatch to automatically mint the dsh-auth session cookie
    // when a trusted identity is present, completely removing the 401 loopback / proxy barrier.
    const originalRegister = this.ctx.webServer.register.bind(this.ctx.webServer);
    const self = this;

    this.ctx.webServer.register = (route: any) => {
      const originalHandler = route.handler;
      route.handler = async (req: IncomingMessage, res: ServerResponse) => {
        const identity = await self.authenticateRequest(req);
        if (identity) {
          // Attach tenant identity to cordis context
          self.ctx.tenant = identity;

          // Auto-mint session cookie if absent so upstream frontend-static & connection are satisfied
          self.ensureSessionCookie(req, res);
        }
        return originalHandler(req, res);
      };
      return originalRegister(route);
    };
  }

  private ensureSessionCookie(req: IncomingMessage, res: ServerResponse): void {
    const hostHeader = req.headers['host'] || '127.0.0.1:3080';
    const authority = hostHeader.split(':')[0] + (hostHeader.includes(':') ? `:${hostHeader.split(':')[1]}` : '');
    const cookieName = 'dsh-auth-' + this.encodeBase64Url(crypto.createHash('sha256').update(authority).digest());

    const existingCookies = req.headers['cookie'] || '';
    if (!existingCookies.includes(cookieName)) {
      const issuedAt = Date.now();
      const expiresAt = issuedAt + 30 * 24 * 60 * 60 * 1000;
      const payload = {
        version: 1,
        authority,
        issuedAt,
        expiresAt
      };
      const body = this.encodeBase64Url(Buffer.from(JSON.stringify(payload), 'utf8'));
      const sig = crypto.createHmac('sha256', this.signingSecret).update(body).digest();
      const cookieValue = `v1.${body}.${this.encodeBase64Url(sig)}`;

      // Inject into incoming request headers so upstream Connection sees it immediately
      req.headers['cookie'] = existingCookies ? `${existingCookies}; ${cookieName}=${cookieValue}` : `${cookieName}=${cookieValue}`;

      // Set cookie on response for browser persistence
      const cookieHeader = `${cookieName}=${cookieValue}; Max-Age=2592000; Path=/; Expires=${new Date(expiresAt).toUTCString()}; HttpOnly; SameSite=Strict`;
      const prevSetCookie = res.getHeader('set-cookie');
      if (prevSetCookie) {
        const list = Array.isArray(prevSetCookie) ? prevSetCookie : [String(prevSetCookie)];
        res.setHeader('set-cookie', [...list, cookieHeader]);
      } else {
        res.setHeader('set-cookie', cookieHeader);
      }
    }
  }

  private encodeBase64Url(buf: Buffer): string {
    return buf.toString('base64').replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
  }
}

export function apply(ctx: Context, config: AuthPluginConfig = {}): void {
  const service = new IdentityAuthGatewayService(ctx, config);
  ctx.auth = service;
}
