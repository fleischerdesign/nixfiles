/**
 * @module dsh-capability/toolgate
 * Extract the capability `resource` a `tools/pre-execute` invocation is asking
 * to touch, so the one `authorise()` primitive can be fed a `path:` resource.
 * This is deliberately *conservative and fail-closed*: if a path-capability tool
 * runs but no raw path can be determined from the invocation, the caller must
 * DENY (never pass through) — an un-authorizable call is exactly the hole the
 * default-deny invariant exists to close (impl-spec §5.3).
 *
 * Note: the upstream fs tools ultimately operate on an opaque `targetKey`; a
 * raw path is available on the model-facing `args` (or the declarative
 * `exec.resource`). Where the backend has already resolved the path, the caller
 * passes that. This module never parses/trusts an opaque key.
 */
export interface ExecInvocation {
  name?: string;
  resource?: string;
  // The upstream `tools/pre-execute` ToolExecutionInput carries the parsed
  // arguments under `arguments` (NOT `args`). FS tools (read/write/edit) use
  // `file_path`; bash/other tools vary. We read `arguments` and fall back to
  // `args` for robustness.
  arguments?: Record<string, any>;
  args?: Record<string, any>;
}

// Upstream FS tools (tool-fs) use `file_path` for read/write/edit. Keep the
// common aliases as a fallback for other tools.
const PATH_TOOL_FILE_KEYS = ['file_path', 'path', 'file', 'target', 'filePath', 'source'];
const PATH_TOOL_LIST_KEYS = ['paths', 'files', 'sources'];

function firstString(v: any): string | undefined {
  if (typeof v === 'string' && v.length > 0) return v;
  if (Array.isArray(v)) {
    for (const e of v) {
      const s = firstString(e);
      if (s) return s;
    }
  }
  return undefined;
}

/**
 * Produce the capability `resource` (a `path:` URI) for a path-capability tool
 * invocation, or `null` when none can be determined. `pathTools` names the
 * tools treated as path-capability tools; tools not in that set return null
 * (they are not path-authorised by this gate).
 */
export function extractResource(exec: ExecInvocation, pathTools: string[]): string | null {
  const tool = exec.name;
  if (!tool || !pathTools.includes(tool)) return null;

  // 1. Explicit declarative resource (the tool/gate may have set exec.resource).
  if (exec.resource && exec.resource.startsWith('path:')) return exec.resource;

  // 2. Raw path from the parsed arguments (upstream: `exec.arguments`).
  const args = exec.arguments ?? exec.args ?? {};
  const raw = firstString(args.file_path) ?? firstString(args.path) ?? firstString(args.file) ?? firstString(args.target);
  if (raw) return `path:${raw}`;

  // 3. A list of paths (e.g. glob, batch) — authorise the first; the caller can
  //    also authorise each. Returning the first keeps the gate single-call.
  for (const k of PATH_TOOL_LIST_KEYS) {
    if (args[k] !== undefined) {
      const list = Array.isArray(args[k]) ? args[k] : [args[k]];
      const s = firstString(list);
      if (s) return `path:${s}`;
    }
  }

  // 4. Batch/bulk file keys.
  for (const k of PATH_TOOL_FILE_KEYS) {
    const s = firstString(args[k]);
    if (s) return `path:${s}`;
  }

  // 5. Fail-closed: no determinable path for a path-capability tool.
  return null;
}

/**
 * Whether the gate can authorise this call at all. A path-capability tool with
 * no determinable path is NOT authorizeable and therefore must be denied when
 * enforcement is on (fail-closed), not passed through.
 */
export function gateDecision(exec: ExecInvocation, pathTools: string[]): { authorizable: boolean; resource: string | null } {
  const resource = extractResource(exec, pathTools);
  return { authorizable: resource !== null, resource };
}
