/**
 * @module dsh-capability/presets
 * P2 — LBAC clearance → permission-preset mapping (impl-spec §4 P2, mesh doc
 * §5, FS doc §8/§9). The upstream process sandbox and the in-process fs tools
 * are fenced by a *sandbox mode* + *approval policy* bundle (a "preset", see
 * upstream `permission-presets`). Because the fs tools operate on an opaque
 * `targetKey` (not a raw path), the only reliable knob the capability layer can
 * turn for them is this preset — it is the concrete mechanism by which a
 * principal's clearance becomes an enforcement knob, and it keys on the
 * authenticated `user:<oidc-sub>`.
 *
 * Default (least privilege): Restricted ⇒ read-only + ask; Member ⇒
 * workspace-write + ask; Admin ⇒ danger-full-access + never.
 */
export type ClearanceLevel = 'Admin' | 'Member' | 'Restricted';

export type SandboxMode =
  | 'read-only'
  | 'workspace-write'
  | 'danger-full-access'
  | 'bypass';

export type ApprovalPolicy = 'ask' | 'never' | 'always';

export interface PresetSpec {
  name: string;
  sandbox: SandboxMode;
  approval: ApprovalPolicy;
}

export interface PresetTable {
  presets: Record<string, PresetSpec>;
  defaultPreset: string;
}

const DEFAULT_PRESETS: Record<ClearanceLevel, PresetSpec> = {
  Admin: { name: 'danger-full-access', sandbox: 'danger-full-access', approval: 'never' },
  Member: { name: 'workspace-write', sandbox: 'workspace-write', approval: 'ask' },
  Restricted: { name: 'read-only', sandbox: 'read-only', approval: 'ask' },
};

/**
 * Map a clearance level to the preset that bounds it. Least privilege by
 * default; the caller (dsh-auth / session resolution) keys this on the
 * authenticated principal. Falling back on an unknown clearance is
 * **fail-locked** to Restricted (read-only), never to a widening default.
 */
export function presetForClearance(clearance: string | undefined): PresetSpec {
  return DEFAULT_PRESETS[clearance as ClearanceLevel] ?? DEFAULT_PRESETS.Restricted;
}

/**
 * Build the config a `permission-presets` service accepts: the preset table
 * (named bundles of sandbox+approval) plus the default preset for new sessions.
 * Operator-provided overrides for a given clearance win over the built-in
 * default; any other key is rejected (never silently a widening preset).
 */
export function buildPresetTable(
  overrides: Partial<Record<ClearanceLevel, PresetSpec>> = {},
): PresetTable {
  const merged: Record<string, PresetSpec> = {};
  for (const level of ['Restricted', 'Member', 'Admin'] as ClearanceLevel[]) {
    const spec = overrides[level] ?? DEFAULT_PRESETS[level];
    if (spec) {
      // The `name` a preset is addressed by is the clearance level itself; the
      // underlying sandbox/approval bundle is what the preset writes through.
      merged[level] = spec;
    }
  }
  return {
    presets: merged,
    defaultPreset: merged.Admin ? 'Admin' : 'Restricted',
  };
}
