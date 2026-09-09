/**
 * @module dsh-capability
 * The capability layer's Cordis shell. The security logic lives in
 * `canonicalize.ts`, `capability.ts` and `authorise.ts` (pure, dependency-free
 * and unit-tested). This module only wires the ONE shared primitive into dsh:
 *
 *   - it provides the `authorise` service so every other plugin (memory,
 *     workspace-tx, share, mesh) asks the same gate,
 *   - it hooks `tools/pre-execute` to default-deny filesystem-tool calls that a
 *     tenant is not granted.
 *
 * A plugin that reads a different policy is a hole (impl-spec §5.3); this
 * module is the place any tool must go through. It never grants on its own —
 * it only ever narrows to the declarative grants (`config.grants`, which are
 * operator-authored claims sealed in the Nix store).
 */
import type { Context } from '@deepseek-ai/cordis';
import { authorise, type Decision, attributionFromDelegation } from './authorise.js';
import type { Action, CapClaims, Resource } from './capability.js';
import { gateDecision } from './toolgate.js';
import { buildPresetTable, presetForClearance, type PresetSpec } from './presets.js';
import { execDecision, isolationPlan } from './isolation.js';
import { toAuditRecord, AuditRing } from './audit.js';

export const name = 'capability';
export const inject = ['tools'];

/** A declarative grant spec (operator-authored, sealed in the Nix store).
 *  `alg: 'hmac-sha256'` is nominal — declarative grants are trusted by origin
 *  (the store), so no runtime signature is required; the field keeps the claim
 *  shape uniform with delegation tokens. */
export interface DeclarativeGrant {
  principal: string;
  resources: Resource[];
  actions: Action[];
  /** Days of validity; 0 (default) = never expires (operator grant). */
  ttlDays?: number;
  budgetEur?: number;
  maxTurns?: number;
}

export interface CapabilityPluginConfig {
  /** Declarative grants — trusted specs; materialized to claims at activation. */
  grants?: DeclarativeGrant[];
  /** Secret/verification key for *delegation capability tokens* (untrusted,
   *  runtime-issued). Absent ⇒ no token grant is accepted (default-deny). */
  verifyKey?: string;
  /** Groups a principal may be a member of (for `group:` grant dominance). */
  groups?: string[];
  /** Tool names that carry a path capability (authorised against `path:`). */
  pathTools?: string[];
  /** Per-clearance preset overrides (P2): key = clearance level, value =
   *  { sandbox, approval }. Merged over the least-privilege defaults. */
  presetOverrides?: Partial<Record<'Restricted' | 'Member' | 'Admin', PresetSpec>>;
  /** Capacity of the in-memory audit ring (P6). */
  auditSize?: number;
  /** When true, the pre-execute gate applies default-deny for ungranted
   *  filesystem-tool calls. When false (default), the gate passes through —
   *  the `authorise` service is still available, but no call is blocked. An
   *  operator opts into enforcement by enabling authorization. */
  enforce?: boolean;
}

declare module '@deepseek-ai/cordis' {
  interface Context {
    capability: {
      authorise(input: {
        principal: string;
        resource: string;
        action: Action;
        viaNode?: string;
        groups?: string[];
      }): Decision;
      /** Evaluate a runtime delegation token as the effective principal. */
      delegate(tokenStr: string, viaNode?: string): Decision | null;
      /** LBAC clearance → permission preset (P2). */
      presetFor(clearance: string | undefined): PresetSpec;
      /** The full preset table with operator overrides (P2). */
      presetTable(): { presets: Record<string, PresetSpec>; defaultPreset: string };
      /** Exec gate: grant + tenant-isolation plan (P5). */
      execPlan(input: { principal: string; resource: string; tenantRoot: string }): {
        allowed: boolean;
        isolation: boolean;
        isolationPlan?: { argv: string[]; bindMasks: { source: string; masked: boolean }[]; apply: boolean };
      };
      /** Leak-free decision log for the transparency panel (P6). */
      auditSnapshot(): import('./audit.js').AuditRecord[];
    };
  }
}

export function apply(ctx: Context, config: CapabilityPluginConfig = {}): void {
  // Materialize declarative grants into full claims AT ACTIVATION, so a TTL
  // ("ttlDays") is computed from the runtime clock (reproducible Nix build, and
  // a real expiry once the process is alive). A declarative grant is a static,
  // operator-authored spec; `iat`/`nonce` are set here, not at build time.
  const now = Date.now();
  const DAY_MS = 86400000;
  const claimOf = (g: DeclarativeGrant): CapClaims => ({
    principal: g.principal,
    resources: g.resources,
    actions: g.actions,
    bounds: {
      ttl: (g.ttlDays ?? 0) > 0 ? now + (g.ttlDays ?? 0) * DAY_MS : 0,
      budgetEur: g.budgetEur,
      maxTurns: g.maxTurns,
    },
    alg: 'hmac-sha256', // nominal: declarative grants are store-sealed, not runtime-signed
    iat: now,
    exp: (g.ttlDays ?? 0) > 0 ? now + (g.ttlDays ?? 0) * DAY_MS : 0,
    nonce: '', // no replay concern; the config itself is the grant
  });
  const declarative = (config.grants ?? []).map(claimOf);
  const groups = config.groups ?? [];

  const svc = {
    // P6: leak-free audit ring — every decision below is recorded here. The
    // ring carries only whitelisted fields (never content), so the transparency
    // panel can answer "who was allowed/denied to do what" without exposing it.
    audit: new AuditRing(config.auditSize ?? 500),
    authorise(input: { principal: string; resource: string; action: Action; viaNode?: string; groups?: string[] }): Decision {
      // Declarative grants are pre-verified by construction (store-sealed). The
      // call is a pure evaluation against the one primitive; default-deny is
      // structural (empty grants ⇒ `deny`). `dominates` uses the LIVE tenant
      // groups (passed by the gate/delegate) merged with any static groups, so
      // a `group:` grant matches the principal's actual IdP memberships — not a
      // hardcoded set.
      const effectiveGroups = [...(input.groups ?? []), ...groups];
      const decision = authorise({
        principal: input.principal,
        groups: effectiveGroups,
        resource: input.resource,
        action: input.action,
        claims: declarative,
      });
      if (config.enforce === true) {
        svc.audit.push(toAuditRecord({
          principal: input.principal,
          resource: input.resource,
          action: input.action,
          result: decision.allowed ? 'allow' : 'deny',
          reason: decision.allowed ? 'granted' : decision.reason ?? 'no grant',
          authority: decision.allowed ? decision.grant?.principal : undefined,
          viaNode: input.viaNode,
        }));
      }
      return decision;
    },
    // Cross-node delegation: extract the USER principal from a token and
    // evaluate it as the effective principal (the node HMAC is only the channel).
    delegate(tokenStr: string, viaNode?: string): Decision | null {
      if (!config.verifyKey) return null;
      const att = attributionFromDelegation(config.verifyKey, tokenStr);
      if (!att) return null;
      return svc.authorise({
        principal: att.principal,
        resource: att.claims.resources[0] ?? '',
        action: (att.claims.actions[0] as Action) ?? 'read',
        viaNode,
      });
    },
    // P2: the sandbox-mode/approval preset that bounds a clearance level. This
    // is what the upstream permission-presets/service reads; the capability
    // layer derives least-privilege (Restricted ⇒ read-only) on unknown input.
    presetFor(clearance: string | undefined) {
      return presetForClearance(clearance);
    },
    // The full preset table (with operator overrides), for a deployment that
    // configures the upstream permission-presets service from this layer.
    presetTable() {
      return buildPresetTable((config.presetOverrides ?? {}) as Record<string, PresetSpec>);
    },
    // P5: does this principal have `exec` on the resource, and if so with what
    // tenant-isolation plan? This is the only place the exec gate should look.
    execPlan(input: { principal: string; resource: string; tenantRoot: string }) {
      const granted = svc.authorise({
        principal: input.principal,
        resource: input.resource,
        action: 'exec',
      }).allowed;
      return execDecision(granted, { tenantRoot: input.tenantRoot, mounts: [] });
    },
    // Audit snapshot for the transparency panel.
    auditSnapshot() {
      return svc.audit.snapshot();
    },
    _isolation: isolationPlan,
  };
  ctx.provide('capability', svc);
  ctx.capability = svc;

  // Glue the filesystem-tool gate onto the same primitive. Coarse LBAC
  // clearance lives in dsh-auth; this is the *capability* dimension: a tool
  // call whose requested `path:`/`resource` the principal is not granted is
  // denied here, at execution time, with no OS fallback.
  const pathTools = config.pathTools ?? [];
  ctx.inject(['tools'], (toolsCtx: any) => {
    toolsCtx.tools.on('tools/pre-execute', async (exec: any, next: () => Promise<any>) => {
      try {
        // Enforcement is opt-in (authorization.enable). When off, the gate is
        // inert and passes through — the authorise service is still provided,
        // but no call is denied. When on, default-deny applies.
        if (config.enforce !== true) return next();

        // The authenticated tenant is a provided service: dsh-auth's `apply`
        // does `ctx.provide('auth', service)` (plus `ctx.auth`), so
        // `ctx.get('auth')` returns the gateway with `.activeTenant` (the OIDC
        // identity + groups). It is NOT on the tools-scoped context, and the
        // bare `ctx.auth` property is only set on dsh-auth's own context —
        // reading either of those silently passed every call through.
        let tenant: { username?: string; groups?: string[] } | undefined;
        try {
          const authService = ctx.get('auth') as any;
          tenant = authService?.activeTenant;
        } catch {
          tenant = undefined;
        }
        const principal = tenant?.username ? `user:${tenant.username}` : '';
        if (!principal) return next(); // no identity ⇒ coarse auth downstream; capability is additive
        const tenantGroups = tenant?.groups ?? [];

        const isPathTool = pathTools.includes(exec?.name ?? '') || (exec?.resource?.startsWith('path:') ?? false);
        if (!isPathTool) return next();

        // Extract the capability resource from the invocation. Fail-closed: a
        // path-capability tool with no determinable path is NOT authorizeable —
        // deny it rather than pass it through.
        const { authorizable, resource } = gateDecision(exec, pathTools);
        const action = (exec?.action as Action) ?? 'read';
        if (!authorizable) {
          return {
            kind: 'deny',
            reason: `Capability denied: no determinable path for ${principal} on tool "${exec?.name}" (${action}).`,
          };
        }
        const decision = svc.authorise({ principal, resource: resource ?? '', action, groups: tenantGroups });
        if (!decision.allowed) {
          return {
            kind: 'deny',
            reason: `Capability denied: ${decision.reason ?? 'no grant'} for ${principal} on ${resource} (${action}).`,
          };
        }
      } catch {
        // Fail closed on an unexpected gate error.
        return { kind: 'deny', reason: 'Capability gate error (fail-closed).' };
      }
      return next();
    });
  });
}
