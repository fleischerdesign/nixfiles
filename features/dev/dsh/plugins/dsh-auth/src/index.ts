import { Service, type Context } from '@deepseek-ai/cordis';
import * as crypto from 'node:crypto';
import * as fs from 'node:fs';
import * as path from 'node:path';
import type { IncomingMessage, ServerResponse } from 'node:http';
import type { AuthPluginConfig, UserIdentity, ClearanceLevel } from './types.js';
import {
  ForwardProxyStrategy,
  LoopbackStrategy,
  PeerMeshStrategy,
  OidcStrategy,
  LdapStrategy,
  type AuthStrategy
} from './strategy.js';
import { PresenceRegistry } from './presence.js';
import {
  OidcFlowStore,
  buildAuthorizeUrl,
  exchangeCode,
  fetchJwks,
  verifyIdToken,
  jwtClaims,
  type OidcFlowConfig,
} from './oidc-flow.js';

export const name = 'auth';
export const inject = ['webServer'];

declare module '@deepseek-ai/cordis' {
  interface Context {
    auth: IdentityAuthGatewayService;
    webServer: any;
    connection?: any;
    tools?: any;
    llm: any;
  }
}

interface TokenBucketState {
  balanceEur: number;
  lastRefillTimestamp: number;
}

export class IdentityAuthGatewayService extends Service {
  public activeTenant?: UserIdentity;
  public presence: PresenceRegistry;
  private strategies: AuthStrategy[] = [];
  private signingSecret: Buffer;
  private tokenBuckets = new Map<string, TokenBucketState>();
  private oidcFlow?: OidcFlowStore;
  private oidcJwks?: { keys: any[]; expiresAt: number };

  constructor(ctx: Context, private config: AuthPluginConfig) {
    super(ctx, 'auth');

    // Initialize strategies based on priority
    this.strategies.push(new PeerMeshStrategy(this.config));
    this.strategies.push(new ForwardProxyStrategy(this.config));
    this.strategies.push(new OidcStrategy(this.config));
    this.strategies.push(new LdapStrategy(this.config));
    this.strategies.push(new LoopbackStrategy(this.config));

    // Load or generate durable cookie signing secret
    this.signingSecret = this.resolveSigningSecret();

    // Tenant-Presence-Registry: which OIDC tenants/groups have been seen here.
    // Feeds agnostic memory-scope peer derivation (docs/dsh/08-...).
    const dshHome = process.env.DSH_HOME || path.join(process.env.HOME || '/root', '.dsh');
    this.presence = new PresenceRegistry(path.join(dshHome, 'auth', 'presence.db'));
    ctx.effect(() => () => this.presence.close());

    // Interactive OIDC (Authorization Code + PKCE) setup when enabled.
    if (this.config.oidc?.enabled) {
      this.setupOidc(ctx);
    }

    // Intercept web requests and connection authorization
    this.interceptWebServer();
    this.interceptConnection();

    // Enforce Lattice-Based Access Control (LBAC) on tool execution
    this.enforceLbacToolPolicy();

    // Enforce Quota & Budget Enforcement (Token-Bucket Theory)
    this.enforceTokenBucketQuota();
  }

  /** Resolve the OIDC flow config (redirect URI defaults to this host:3080). */
  private oidcCfg(): OidcFlowConfig {
    const o = this.config.oidc!;
    const redirectUri = o.redirectUri || `http://127.0.0.1:3080/oidc/callback`;
    return {
      issuer: o.issuer,
      clientId: o.clientId,
      clientSecret: o.clientSecret,
      redirectUri,
      scopes: o.scopes || ['openid', 'profile', 'email'],
      logoutUri: o.logoutUri,
    };
  }

  /** Register the OIDC callback + logout routes (raw, before the interceptor). */
  private setupOidc(ctx: Context): void {
    this.oidcFlow = new OidcFlowStore();
    ctx.inject(['webServer'], (wsCtx: any) => {
      wsCtx.webServer.register({
        kind: 'exact',
        path: '/oidc/callback',
        handler: async (req: any, res: any) => { await this.handleOidcCallback(req, res); },
      });
      wsCtx.webServer.register({
        kind: 'exact',
        path: '/oidc/logout',
        handler: async (req: any, res: any) => { this.handleOidcLogout(req, res); },
      });
    });
  }

  private async handleOidcCallback(req: any, res: any): Promise<void> {
    const url = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`);
    const code = url.searchParams.get('code');
    const state = url.searchParams.get('state');
    if (!code || !state) { res.writeHead(400); res.end('Missing code/state'); return; }
    const entry = this.oidcFlow?.consume(state);
    if (!entry) { res.writeHead(400); res.end('Invalid or expired state'); return; }
    try {
      const cfg = this.oidcCfg();
      const tokens = await exchangeCode(cfg, { code, verifier: entry.verifier });
      const jwks = await this.jwks();
      const claims = verifyIdToken({
        idToken: tokens.id_token || '',
        jwks,
        issuer: cfg.issuer,
        audience: cfg.clientId,
        nonce: entry.nonce,
      });
      const identity = this.mapOidcIdentity(claims);
      this.presence.noteTenant(identity);
      this.ensureSessionCookie(req, res, identity);
      res.writeHead(302, { Location: entry.redirectTo || '/' });
      res.end();
    } catch (e: any) {
      res.writeHead(401);
      res.end(`OIDC login failed: ${e.message || String(e)}`);
    }
  }

  private handleOidcLogout(req: any, res: any): void {
    // Clear the dsh session cookie; optionally forward to Authentik end_session.
    const logoutUri = this.oidcCfg().logoutUri;
    const resUrl = logoutUri ? `${logoutUri}?client_id=${encodeURIComponent(this.config.oidc!.clientId)}` : '/';
    const hostHeader = req.headers['host'] || '127.0.0.1:3080';
    const authority = new URL(`http://${hostHeader}`).host;
    const cookieName = 'dsh-auth-' + this.encodeBase64Url(crypto.createHash('sha256').update(authority).digest());
    res.setHeader('Set-Cookie', `${cookieName}=; Max-Age=0; Path=/; HttpOnly; SameSite=Lax`);
    res.writeHead(302, { Location: resUrl });
    res.end();
  }

  private async jwks(): Promise<any[]> {
    const cfg = this.oidcCfg();
    if (this.oidcJwks && this.oidcJwks.expiresAt > Date.now()) return this.oidcJwks.keys;
    const keys = await fetchJwks(cfg);
    this.oidcJwks = { keys, expiresAt: Date.now() + 3600_000 };
    return keys;
  }

  private mapOidcIdentity(claims: any): UserIdentity {
    const username = claims.preferred_username || claims.sub || claims.name || 'oidc-user';
    const groups: string[] = Array.isArray(claims.groups) ? claims.groups : [];
    const adminClaim = this.config.oidc?.adminClaim || 'groups';
    const adminVals = this.config.oidc?.adminValues || ['admin', 'admins', 'authentik Admins'];
    const uc = claims[adminClaim];
    const isAdmin = Array.isArray(uc) ? uc.some((v: string) => adminVals.includes(v)) : (typeof uc === 'string' && adminVals.includes(uc));
    return {
      id: `usr_${username}`,
      username,
      email: claims.email,
      displayName: claims.name,
      groups,
      clearance: isAdmin ? 'Admin' : 'Member',
      provider: 'oidc',
    };
  }

  /** Paths that must NOT trigger an OIDC redirect (callback itself, assets, health). */
  private isPublicPath(p: string): boolean {
    return p.startsWith('/oidc/')
      || p === '/favicon.ico'
      || p.startsWith('/assets/')
      || p === '/health' || p.startsWith('/api/health')
      || /\.(js|css|png|svg|ico|woff2?|map|json|txt)$/.test(p);
  }

  private resolveSigningSecret(): Buffer {
    // Check if credentials.yaml has client-connection/browser-session secret
    const credPath = `${process.env.DSH_HOME || process.env.HOME + '/.dsh'}/.credentials.yaml`;
    try {
      if (fs.existsSync(credPath)) {
        const content = fs.readFileSync(credPath, 'utf8');
        // Check JSON first
        try {
          const doc = JSON.parse(content);
          const secStr = doc?.records?.['client-connection/browser-session']?.payload?.secret;
          if (secStr) {
            const padding = '='.repeat((4 - secStr.length % 4) % 4);
            return Buffer.from(secStr.replaceAll('-', '+').replaceAll('_', '/') + padding, 'base64');
          }
        } catch {
          // Fall through to regex
        }
        // Match "secret: <base64url>" or '"secret": "<base64url>"'
        const match = content.match(/secret:\s*["']?([A-Za-z0-9_-]+)["']?/);
        if (match && match[1]) {
          const secStr = match[1];
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
    // 1. Try strategy authentication first (Header, JWT, PeerMesh, Loopback)
    const remoteIp = req.socket.remoteAddress?.replace(/^.*:/, '') || '127.0.0.1';
    for (const strategy of this.strategies) {
      if (strategy.canHandle(req, remoteIp)) {
        const identity = await strategy.authenticate(req, remoteIp);
        if (identity) return identity;
      }
    }

    // 2. Try restoring identity from validated session cookie
    const cookieIdentity = this.extractIdentityFromCookie(req);
    if (cookieIdentity) {
      return cookieIdentity;
    }

    return null;
  }

  private extractIdentityFromCookie(req: IncomingMessage): UserIdentity | null {
    const hostHeader = req.headers['host'] || '127.0.0.1:3080';
    let authority: string;
    try {
      authority = new URL(`http://${hostHeader}`).host;
    } catch {
      authority = hostHeader;
    }

    const cookieName = 'dsh-auth-' + this.encodeBase64Url(crypto.createHash('sha256').update(authority).digest());
    const cookieHeader = req.headers['cookie'] || '';
    if (!cookieHeader) return null;

    const cookies = cookieHeader.split(';').map(c => c.trim());
    for (const cookie of cookies) {
      if (cookie.startsWith(`${cookieName}=`)) {
        const rawValue = cookie.slice(cookieName.length + 1);
        const parts = rawValue.split('.');
        if (parts.length === 3 && parts[0] === 'v1') {
          const body = parts[1];
          const sig = parts[2];
          const expectedSig = this.encodeBase64Url(
            crypto.createHmac('sha256', this.signingSecret).update(body).digest()
          );

          if (sig === expectedSig) {
            try {
              const decodedJson = Buffer.from(body, 'base64url').toString('utf8');
              const payload = JSON.parse(decodedJson);
              const now = Date.now();
              if (payload.expiresAt && payload.expiresAt > now && payload.identity) {
                return payload.identity;
              }
            } catch {
              // Corrupted cookie body
            }
          }
        }
      }
    }
    return null;
  }

  private interceptWebServer(): void {
    const originalRegister = this.ctx.webServer.register.bind(this.ctx.webServer);
    const self = this;

    this.ctx.webServer.register = (route: any) => {
      const originalHandler = route.handler;
      route.handler = async (req: IncomingMessage, res: ServerResponse) => {
        const identity = await self.authenticateRequest(req);
        if (identity) {
          // Attach tenant identity to request and service
          (req as any).tenant = identity;
          self.activeTenant = identity;
          // Record presence for agnostic memory-scope peer derivation.
          try { self.presence.noteTenant(identity); } catch { /* non-fatal */ }

          // Auto-mint session cookie if absent or renew with full tenant identity
          self.ensureSessionCookie(req, res, identity);
        } else if (self.oidcFlow && self.config.oidc?.enabled && !self.isPublicPath(req.url || '/')) {
          // Interactive OIDC: no identity and this is a gated app route -> redirect.
          const flow = self.oidcFlow.begin();
          const loc = buildAuthorizeUrl(self.oidcCfg(), {
            state: flow.state,
            nonce: flow.nonce,
            challenge: flow.challenge,
            method: 'S256',
          });
          res.writeHead(302, { Location: loc });
          res.end();
          return;
        }
        return originalHandler(req, res);
      };
      return originalRegister(route);
    };
  }

  private ensureSessionCookie(req: IncomingMessage, res: ServerResponse, identity?: UserIdentity): void {
    const hostHeader = req.headers['host'] || '127.0.0.1:3080';
    let authority: string;
    try {
      authority = new URL(`http://${hostHeader}`).host;
    } catch {
      authority = hostHeader;
    }
    const cookieName = 'dsh-auth-' + this.encodeBase64Url(crypto.createHash('sha256').update(authority).digest());

    const existingCookies = req.headers['cookie'] || '';
    // If cookie is absent or if we need to embed identity
    if (!existingCookies.includes(cookieName)) {
      const issuedAt = Date.now();
      const expiresAt = issuedAt + (this.config.sessionTtlDays || 30) * 24 * 60 * 60 * 1000;
      const resolvedIdentity: UserIdentity = identity || {
        id: `usr_local`,
        username: 'local',
        groups: ['wheel'],
        clearance: 'Admin',
        provider: 'loopback'
      };

      const payload = {
        version: 1,
        authority,
        issuedAt,
        expiresAt,
        identity: resolvedIdentity
      };
      const body = this.encodeBase64Url(Buffer.from(JSON.stringify(payload), 'utf8'));
      const sig = crypto.createHmac('sha256', this.signingSecret).update(body).digest();
      const cookieValue = `v1.${body}.${this.encodeBase64Url(sig)}`;

      // Inject into incoming request headers so upstream Connection sees it immediately
      req.headers['cookie'] = existingCookies ? `${existingCookies}; ${cookieName}=${cookieValue}` : `${cookieName}=${cookieValue}`;

      // Set cookie on response for browser persistence
      const maxAge = (this.config.sessionTtlDays || 30) * 86400;
      const cookieHeader = `${cookieName}=${cookieValue}; Max-Age=${maxAge}; Path=/; Expires=${new Date(expiresAt).toUTCString()}; HttpOnly; SameSite=Strict`;
      const prevSetCookie = res.getHeader('set-cookie');
      if (prevSetCookie) {
        const list = Array.isArray(prevSetCookie) ? prevSetCookie : [String(prevSetCookie)];
        res.setHeader('set-cookie', [...list, cookieHeader]);
      } else {
        res.setHeader('set-cookie', cookieHeader);
      }
    }
  }

  private interceptConnection(): void {
    const self = this;
    // When connection service becomes available, wrap authorizeIndex and requestRejection
    this.ctx.inject(['connection'], (connCtx) => {
      const conn = connCtx.connection;
      if (!conn) return;

      const originalAuthorizeIndex = conn.authorizeIndex?.bind(conn);
      if (originalAuthorizeIndex) {
        conn.authorizeIndex = (req: any, res: any) => {
          const remoteIp = req.socket?.remoteAddress?.replace(/^.*:/, '') || '127.0.0.1';
          for (const strategy of self.strategies) {
            if (strategy.canHandle(req, remoteIp)) {
              // Ensure the browser session cookie is minted
              self.ensureSessionCookie(req, res);
              return true;
            }
          }
          if (self.extractIdentityFromCookie(req)) {
            return true;
          }
          return originalAuthorizeIndex(req, res);
        };
      }

      const originalRequestRejection = conn.requestRejection?.bind(conn);
      if (originalRequestRejection) {
        conn.requestRejection = (req: any) => {
          const remoteIp = req.socket?.remoteAddress?.replace(/^.*:/, '') || '127.0.0.1';
          for (const strategy of self.strategies) {
            if (strategy.canHandle(req, remoteIp)) {
              return undefined; // Authorized!
            }
          }
          if (self.extractIdentityFromCookie(req)) {
            return undefined; // Valid session cookie!
          }
          return originalRequestRejection(req);
        };
      }

      const originalAuthenticatedUrl = conn.authenticatedUrl?.bind(conn);
      if (originalAuthenticatedUrl) {
        conn.authenticatedUrl = (baseUrl: string) => {
          const url = new URL(baseUrl);
          url.pathname = '/';
          url.search = '';
          url.hash = '';
          return url.href;
        };
      }
    });
  }

  /**
   * Enforce Lattice-Based Access Control (LBAC):
   * R = { Restricted, Member, Admin } with Restricted < Member < Admin
   *
   * Capability Classification:
   * - T_Restricted (lambda <= Restricted): search_web, calculator, read_own_workspace, summarize
   * - T_Member (lambda <= Member): T_Restricted + hass_control, paperless_query, browser_sandbox, vikunja_tasks
   * - T_Admin (lambda <= Admin): T_Member + exec_shell, git_mutate, nix_rebuild, cluster_orchestrate, secret_access, workspace_commit
   */
  private enforceLbacToolPolicy(): void {
    const self = this;

    const ADMIN_ONLY_TOOLS = new Set([
      'exec_shell',
      'tool-bash',
      'bash',
      'pwsh',
      'git_mutate',
      'nix_rebuild',
      'cluster_orchestrate',
      'secret_access',
      'workspace_commit'
    ]);

    const MEMBER_OR_ABOVE_TOOLS = new Set([
      'hass_control',
      'paperless_query',
      'browser_sandbox',
      'vikunja_tasks',
      'workspace_propose_mutation'
    ]);

    this.ctx.inject(['tools'], (toolsCtx: any) => {
      toolsCtx.tools.on('tools/pre-execute', async function(exec: any, next: () => Promise<any>) {
        const tenant = self.activeTenant;
        const clearance: ClearanceLevel = tenant?.clearance || 'Admin'; // Default to Admin for local loopback

        const toolName = exec.name;

        // Admin has universal clearance
        if (clearance === 'Admin') {
          return next();
        }

        // Check Restricted clearance
        if (clearance === 'Restricted') {
          if (ADMIN_ONLY_TOOLS.has(toolName) || MEMBER_OR_ABOVE_TOOLS.has(toolName)) {
            return {
              kind: 'deny',
              reason: `MTAA Lattice Violation: Tool "${toolName}" requires clearance >= Member (current tenant clearance: ${clearance}).`
            };
          }
        }

        // Check Member clearance
        if (clearance === 'Member') {
          if (ADMIN_ONLY_TOOLS.has(toolName)) {
            return {
              kind: 'deny',
              reason: `MTAA Lattice Violation: Tool "${toolName}" requires clearance == Admin (current tenant clearance: ${clearance}).`
            };
          }
        }

        return next();
      });
    });
  }

  /**
   * Enforce Deterministic Leaky Token-Bucket Budget Algorithm (Section 4):
   *
   *   B_u(t) = min(C_max, B_u(t_0) + rho * (t - t_0)) - Cost(turn)
   *
   * Fail-Closed Invariant:
   *   Before dispatching a prompt to any upstream LLM adapter:
   *   if B_u(t) <= 0 => Deny request with BudgetExceededException before opening network connection.
   */
  private enforceTokenBucketQuota(): void {
    const self = this;

    // Default quota policy per clearance:
    // Admin: Unbounded (null)
    // Member: C_max = 15.0 EUR, rho = 15.0 / 30 days = ~5.78e-6 EUR/s
    // Restricted: C_max = 5.0 EUR, rho = 5.0 / 30 days = ~1.93e-6 EUR/s
    const DEFAULT_CAPS: Record<ClearanceLevel, { max: number; refill: number } | null> = {
      Admin: null,
      Member: { max: 15.0, refill: 15.0 / (30 * 86400) },
      Restricted: { max: 5.0, refill: 5.0 / (30 * 86400) }
    };

    this.ctx.inject(['llm'], (llmCtx: any) => {
      llmCtx.llm.on('llm/pre-request', async function(request: any, next: () => Promise<any>) {
        const tenant = self.activeTenant;
        const clearance: ClearanceLevel = tenant?.clearance || 'Admin';
        const tenantId = tenant?.id || 'usr_local';

        const configuredQuota = self.config.quotas?.[clearance];
        const defaultCap = DEFAULT_CAPS[clearance];

        // If unbounded (Admin), permit immediately
        if (!configuredQuota && defaultCap === null) {
          return next();
        }

        const maxBudget = configuredQuota?.maxBudgetEur ?? defaultCap?.max ?? 15.0;
        const refillRate = configuredQuota?.refillRatePerSec ?? defaultCap?.refill ?? (maxBudget / (30 * 86400));

        const now = Date.now();
        let bucket = self.tokenBuckets.get(tenantId);
        if (!bucket) {
          bucket = {
            balanceEur: maxBudget,
            lastRefillTimestamp: now
          };
          self.tokenBuckets.set(tenantId, bucket);
        } else {
          // Refill tokens: delta_t * rho
          const elapsedSec = (now - bucket.lastRefillTimestamp) / 1000;
          if (elapsedSec > 0) {
            bucket.balanceEur = Math.min(maxBudget, bucket.balanceEur + (refillRate * elapsedSec));
            bucket.lastRefillTimestamp = now;
          }
        }

        // Fail-Closed Invariant: check worst-case cost margin before model call
        const ESTIMATED_MIN_COST_EUR = 0.0005; // 0.05 cent safety margin
        if (bucket.balanceEur < ESTIMATED_MIN_COST_EUR) {
          const err = new Error(
            `BudgetExceededException: Tenant "${tenantId}" (${clearance}) token-bucket balance (${bucket.balanceEur.toFixed(4)} €) is depleted. Spending ceiling C_max = ${maxBudget} €.`
          );
          (err as any).code = 'BUDGET_EXCEEDED';
          throw err;
        }

        const response = await next();

        // Deduct actual cost post-request if meter data is available
        const promptTokens = response?.usage?.promptTokens || request?.messages?.length * 100 || 100;
        const completionTokens = response?.usage?.completionTokens || 100;
        // Approximation: ~0.14 € per 1M prompt tokens, ~0.28 € per 1M completion tokens (DeepSeek v3)
        const costEur = (promptTokens * 0.00000014) + (completionTokens * 0.00000028);
        bucket.balanceEur = Math.max(0, bucket.balanceEur - costEur);

        return response;
      });
    });
  }

  private encodeBase64Url(buf: Buffer): string {
    return buf.toString('base64').replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
  }
}

export function apply(ctx: Context, config: AuthPluginConfig = {}): void {
  const service = new IdentityAuthGatewayService(ctx, config);
  ctx.auth = service;
}
