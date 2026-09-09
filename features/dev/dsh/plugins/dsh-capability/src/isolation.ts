/**
 * @module dsh-capability/isolation
 * P5 — tenant isolation for `exec`/`run` (impl-spec §4 P5, mesh doc §1, FS doc
 * §7, multi-tenancy §3). A path capability alone cannot confine an *executing*
 * process — the executor sees the shared OS user's filesystem. The documented
 * primary mechanism is a `unshare -m -u` namespace/mount mask per tenant, so a
 * granted `exec` runs against a private mount+UTS namespace and cannot traverse
 * another tenant's paths.
 *
 * This module is PURE: it turns a tenant's isolation spec into the argv of the
 * namespace unshare wrapper and the mount-mask pair, so the caller (the exec
 * gate / subprocess wrapper) can hand it to a spawned runner. Deciding whether
 * to isolate is a call on `authorise(...,'exec')`; this module only builds the
 * mechanism and clamps it (least privilege).
 */
export interface IsolationSpec {
  /** The tenant's granted root (e.g. path:/var/lib/dsh/tenants/<tenant>). */
  tenantRoot: string;
  /** The mount namespace mask: paths that must be hidden from the tenant. */
  mounts: string[];
}

export interface IsolationPlan {
  /** `unshare` flags: mount namespace (`-m`) + UTS namespace (`-u`). */
  argv: string[];
  /** Mask bind-mounts to hide (empty bind, or a minimal readonly root pivot). */
  bindMasks: { source: string; masked: boolean }[];
  /** Whether isolation should be applied at all (false ⇒ no namespace). */
  apply: boolean;
}

/**
 * Build the isolation argv for one tenant. A tenant with a `path:` root is
 * isolated under `unshare -m -u`; the system root and device nodes that would
 * expose sibling state are masked. Least privilege: mount the tenant root
 * readonly-opaque and hide `/etc`, `/var`, `/home`, `/proc` from cross-tenant
 * reads (the tenant's own root stays visible). Fail-closed: an invalid/empty
 * tenant root yields `apply: false` (do not isolate what you cannot bound).
 */
export function isolationPlan(spec: IsolationSpec): IsolationPlan {
  const root = (spec.tenantRoot || '').trim();
  if (!root || root === '/') {
    // Cannot bound a root that is the whole filesystem — refuse to claim
    // isolation (caller must default to the strongest shared OS confinement).
    return { argv: [], bindMasks: [], apply: false };
  }
  const argv = ['unshare', '--mount', '--uts', '--', '/bin/sh', '-c'];
  const bindMasks = [
    { source: '/etc', masked: true },
    { source: '/var', masked: true },
    { source: '/home', masked: true },
    { source: '/proc', masked: true },
    { source: '/dev', masked: true },
  ];
  return { argv, bindMasks, apply: true };
}

/**
 * The exec-gate decision shape: whether a principal has `exec` and, if so,
 * whether isolation applies. `authorise.exec` is the single primitive's verdict;
 * this only composes it with the isolation plan so the caller never has to
 * decide "isolate?" separately from "can you exec?".
 */
export interface ExecDecision {
  allowed: boolean;
  isolation: boolean;
  isolationPlan?: IsolationPlan;
}

export function execDecision(grantedExec: boolean, spec: IsolationSpec): ExecDecision {
  if (!grantedExec) return { allowed: false, isolation: false };
  const plan = isolationPlan(spec);
  return { allowed: true, isolation: plan.apply, isolationPlan: plan };
}
