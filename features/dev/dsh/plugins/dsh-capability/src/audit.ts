/**
 * @module dsh-capability/audit
 * P6 — audit / transparency decision-log record (impl-spec §4 P6, mesh doc §6.4).
 * Every `authorise()` call is to be observed as a structured, immutable, leaking-
 * free record so an operator can answer "who was allowed/denied to do what,
 * when, on whose authority" — the transparency panel's data source. The record
 * deliberately carries ZERO content: it records the *decision* (principal,
 * resource URI, action, reason, authority) — never the payload (file contents,
 * secret, page). `authorise` stays side-effect-free; the caller emits the
 * record via the plugin's `record` sink, so the primitive is not coupled to the
 * log store.
 */
export interface AuditRecord {
  /** Epoch ms of the decision. */
  at: number;
  /** The effective principal (a user URI on a cross-node call). */
  principal: string;
  /** The requested resource URI (node:/tool:/scope:/path:). */
  resource: string;
  /** The requested action. */
  action: string;
  /** `allow` | `deny`. */
  result: 'allow' | 'deny';
  /** The verdict reason (`deny`/`expired`/`replayed`/`no grant`). */
  reason: string;
  /** The grant/principal that conferred the allow (when allowed). */
  authority?: string;
  /** Cross-node: present when the decision was evaluated for a delegating principal. */
  viaNode?: string;
}

/** Field whitelist for a leak-free serialization of an AuditRecord. */
export const AUDIT_FIELD_ORDER: readonly (keyof AuditRecord)[] = [
  'at',
  'principal',
  'resource',
  'action',
  'result',
  'reason',
  'authority',
  'viaNode',
];

/**
 * Normalize a decision into a leak-free audit record. Any extra property on the
 * input (e.g. a payload accidentally attached) is dropped; only whitelisted
 * fields survive. This makes a leak structurally impossible at the boundary.
 */
export function toAuditRecord(input: {
  at?: number;
  principal: string;
  resource: string;
  action: string;
  result: 'allow' | 'deny';
  reason: string;
  authority?: string;
  viaNode?: string;
}): AuditRecord {
  const rec: AuditRecord = {
    at: input.at ?? Date.now(),
    principal: input.principal,
    resource: input.resource,
    action: input.action,
    result: input.result,
    reason: input.reason,
  };
  if (input.authority !== undefined) rec.authority = input.authority;
  if (input.viaNode !== undefined) rec.viaNode = input.viaNode;
  return rec;
}

/** Serialize to the exact, ordered whitelist — nothing else can leak. */
export function serializeRecord(rec: AuditRecord): string {
  return JSON.stringify(
    AUDIT_FIELD_ORDER.reduce<Record<string, unknown>>((acc, k) => {
      const v = rec[k];
      if (v !== undefined) acc[k] = v;
      return acc;
    }, {}),
  );
}

/** In-memory ring that retains the last N records for the transparency panel. */
export class AuditRing {
  private buf: AuditRecord[] = [];
  constructor(private capacity = 500) {}
  push(rec: AuditRecord): void {
    this.buf.push(rec);
    if (this.buf.length > this.capacity) this.buf.shift();
  }
  snapshot(): AuditRecord[] {
    return this.buf.slice();
  }
  clear(): void {
    this.buf = [];
  }
}
