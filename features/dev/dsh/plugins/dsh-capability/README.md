# dsh-capability

Granular, capability-based authorization for the dsh agent mesh. This plugin
implements the **P1 policy primitive** of `docs/implementation-spec.md` — the
canonicalizer, the prefix automaton, and the **one shared `authorise()`** —
plus the capability token model. It is additive and opt-in: when disabled it
provides the `authorise` service but never blocks a call; when enabled it
enforces **default-deny** against the operator's declarative grants.

> **Design rule (impl-spec §5.3):** there is exactly one authorization
> primitive. Every path-authoritative tool and the exec gate must go through
> it. A tool that reads a different policy is a hole.

## What this plugin provides

| Symbol | File | Role |
|---|---|---|
| `canonicalize(path)` | `src/canonicalize.ts` | fail-closed path canonicalization (NUL / control reject, absolute-required, `.`/`..` condense, root-escape reject) |
| `isWithinRoot(root, path)` | `src/canonicalize.ts` | boundary-safe prefix containment (`/etc` ∌ `/etcd`) |
| `compileRoot(root)` | `src/canonicalize.ts` | prefix automaton predicate for a `path:` root |
| `createToken` / `verifyToken` / `attenuate` | `src/capability.ts` | signed, attenuable capability token with the full tuple (`principal`, `resources`, `actions`, `bounds`) |
| `authorise(...)` | `src/authorise.ts` | **the** primitive: principal dominance → resource match (prefix for `path:`) → action → bounds → deny |
| `authoriseToken` / `attributionFromDelegation` | `src/authorise.ts` | delegation-token + cross-node user attribution |
| `apply()` (Cordis) | `src/index.ts` | provides the `authorise` service + `tools/pre-execute` gate |
| `extractResource` / `gateDecision` | `src/toolgate.ts` | deterministic, fail-closed resource extraction for the fs gate (V-fail-closed) |
| `presetForClearance` / `buildPresetTable` | `src/presets.ts` | P2: LBAC clearance → sandbox/approval preset (least privilege) |

## The capability tuple

```ts
{
  principal: 'user:<oidc-sub>' | 'group:<g>' | 'node:<id>',  // who holds it
  resources: ['node:strummer', 'tool:filesystem.read', 'scope:user:<sub>', 'path:/etc/nixos/**'],
  actions:   ['read','list','write','mutate','exec','orchestrate','replicate'],  // canonical verb set
  bounds:    { ttl, budgetEur, maxTurns, maxDepth },
  attestation: /* signed, attenuable, revocable */
}
```

`path:` resources are matched by **prefix containment**, never string equality;
`node:all` / `tool:*` wildcards resolve here. Non-widening attenuation is
enforced structurally (a child may only be a subset of its parent — V12).

## Declarative grants (Nix)

Grants are operator-authored and sealed in the Nix store; they are materialized
to runtime claims at plugin activation (so `ttlDays` is a real, runtime expiry).
A principal with no matching grant is **denied by default** when enforcement is
on.

```nix
my.features.dev.dsh.authorization = {
  enable = true;
  pathTools = [ "read" "write" "edit" "glob" "bash" ];
  grants = [
    {
      principal = "user:<friend-sub>";
      resources = [ "path:/srv/media/**" "node:mackaye" ];
      actions = [ "read" "list" ];
      ttlDays = 30;
      budgetEur = 3.0;
    }
  ];
};
```

## Verification

```bash
# 1. Compile the pure core + Cordis shell against real dsh types:
#    (scratch: symlink @deepseek-ai + @types/node from the dsh package, run tsc)
# 2. Run the matrix unit tests:
node --test test/capability.test.mjs
# 3. Gate: nix flake check
```

The unit suite covers the verification-matrix rows V1–V6, V11–V15 at the
primitive level (default-deny, granted read/write, sibling deny, symlink escape,
`..` traversal, action-not-granted, wrong principal, group dominance, expiry,
bad signature, single-source-of-truth, non-widening attenuation, token
roundtrip, delegation attribution, cross-node user evaluation), plus the P2
preset mapping and the fail-closed tool gate.

## Scope (honest framing)

This delivers **P1**, **P2**, and the capability-token model P3/P4 build on.
P5 (`unshare` tenant isolation for `exec`), the full P4 PeerMeshStrategy
delegation flow, and P6 (ergonomics/audit UI) are iterated in the next phases —
see `docs/implementation-spec.md`. The upstream process sandbox
(`fs-sandbox`/`sandbox-policy`/`permission-presets`) is not edited here; this
plugin sits above it as the logical per-principal gate, and P2 turns the
authenticated clearance into the sandbox-mode/approval preset that gates it.
