import * as fs from 'node:fs';
import * as path from 'node:path';
import * as crypto from 'node:crypto';
import { execSync } from 'node:child_process';

/**
 * Normalizes a raw git remote origin URL (HTTP, HTTPS, SSH, git) into a canonical locator.
 * Example:
 *  - "https://github.com/fleischerdesign/commpact-ui.git" -> "github.com/fleischerdesign/commpact-ui"
 *  - "git@github.com:fleischerdesign/commpact-ui.git" -> "github.com/fleischerdesign/commpact-ui"
 */
export function normalizeGitOrigin(rawUrl: string): string {
  let url = rawUrl.trim();
  url = url.replace(/\.git$/, '');
  url = url.replace(/^git@([^:]+):/, '$1/');
  url = url.replace(/^https?:\/\//, '');
  url = url.replace(/^ssh:\/\/git@/, '');
  url = url.replace(/^ssh:\/\//, '');
  return url;
}

/**
 * Computes a portable, canonical Workspace URN for cross-host session identity.
 *
 * Pattern:
 * 1. Git-Anchored: urn:dsh:workspace:git:<canonicalRepo>[:<subpath>]
 *    e.g. urn:dsh:workspace:git:github.com/fleischerdesign/commpact-ui
 * 2. Home-Relative: urn:dsh:workspace:relhome:<relative/path>
 *    e.g. urn:dsh:workspace:relhome:dev/commpact-ui
 * 3. Fallback Absolute: urn:dsh:workspace:raw:<sha256(absPath)>
 */
export function computeCanonicalWorkspaceUrn(cwd: string): {
  urn: string;
  type: 'git' | 'relhome' | 'raw';
  label: string;
  meta?: Record<string, string>;
} {
  const resolved = path.resolve(cwd);

  // 1. Try Git resolution
  try {
    const gitDir = execSync('git rev-parse --show-toplevel', {
      cwd: resolved,
      stdio: ['ignore', 'pipe', 'ignore'],
      encoding: 'utf8'
    }).trim();

    if (gitDir && fs.existsSync(gitDir)) {
      let originUrl = '';
      try {
        originUrl = execSync('git config --get remote.origin.url', {
          cwd: gitDir,
          stdio: ['ignore', 'pipe', 'ignore'],
          encoding: 'utf8'
        }).trim();
      } catch {
        // No remote origin configured
      }

      const repoBaseName = path.basename(gitDir);
      const subpath = path.relative(gitDir, resolved);

      if (originUrl) {
        const canonicalRepo = normalizeGitOrigin(originUrl);
        const urn = `urn:dsh:workspace:git:${canonicalRepo}${subpath ? `:${subpath}` : ''}`;
        return {
          urn,
          type: 'git',
          label: repoBaseName,
          meta: {
            gitDir,
            originUrl,
            canonicalRepo,
            subpath,
            repoName: repoBaseName
          }
        };
      }

      // Local git repo without remote origin
      const anchorHash = crypto.createHash('sha256').update(gitDir).digest('hex').substring(0, 16);
      return {
        urn: `urn:dsh:workspace:git:${repoBaseName}:${anchorHash}${subpath ? `:${subpath}` : ''}`,
        type: 'git',
        label: repoBaseName,
        meta: {
          gitDir,
          subpath,
          repoName: repoBaseName
        }
      };
    }
  } catch {
    // Not a git repository
  }

  // 2. Try home-relative path resolution
  const home = process.env.HOME || '/root';
  if (resolved.startsWith(home)) {
    const rel = path.relative(home, resolved);
    const label = path.basename(resolved);
    return {
      urn: `urn:dsh:workspace:relhome:${rel}`,
      type: 'relhome',
      label,
      meta: { relPath: rel }
    };
  }

  // 3. Raw absolute path hash
  const rawHash = crypto.createHash('sha256').update(resolved).digest('hex').substring(0, 16);
  return {
    urn: `urn:dsh:workspace:raw:${rawHash}`,
    type: 'raw',
    label: path.basename(resolved),
    meta: { rawPath: resolved }
  };
}

/**
 * Extracts the authoritative execution cwd directly from the session file's header.
 * DSH session.v2.jsonl.zstd files contain a JSON object in line 1 with { type: 'session', cwd: '...' }.
 */
export function extractCwdFromSessionDir(sessionDirPath: string): string | null {
  const zstdFile = path.join(sessionDirPath, 'session.v2.jsonl.zstd');
  if (fs.existsSync(zstdFile)) {
    try {
      const out = execSync(`zstd -dc "${zstdFile}" 2>/dev/null | head -n 1`, {
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'ignore'],
        timeout: 2000
      });
      const header = JSON.parse(out.trim());
      if (typeof header.cwd === 'string' && header.cwd.length > 0) {
        return header.cwd;
      }
    } catch {
      // Fallback if zstd extraction fails
    }
  }
  return null;
}

/**
 * Resolves a DSH hashed directory name like "--home-philipp-dev-commpact-ui--"
 * back into its real filesystem path.
 *
 * Algorithm:
 * 1. If any child session has a readable header cwd, use that verified path.
 * 2. Otherwise, perform a smart filesystem walk matching hyphens against real directories.
 */
export function resolveWorkspacePath(wsDirName: string, sessionsParentDir?: string): string {
  if (sessionsParentDir) {
    const candidateWsDir = path.join(sessionsParentDir, wsDirName);
    if (fs.existsSync(candidateWsDir)) {
      try {
        const entries = fs.readdirSync(candidateWsDir);
        for (const entry of entries) {
          if (entry.startsWith('session-')) {
            const cwd = extractCwdFromSessionDir(path.join(candidateWsDir, entry));
            if (cwd && fs.existsSync(cwd)) {
              return cwd;
            }
          }
        }
      } catch {
        // Continue to heuristic
      }
    }
  }

  if (!wsDirName.startsWith('--') || !wsDirName.endsWith('--')) {
    return wsDirName;
  }

  const inner = wsDirName.slice(2, -2);
  const parts = inner.split('-');

  // Best-effort path reconstruction against filesystem
  let current = '/';
  let i = 0;
  while (i < parts.length) {
    if (!parts[i]) {
      i++;
      continue;
    }
    // Greedily find the longest valid directory match (e.g. "commpact-ui")
    let matched = false;
    for (let j = parts.length; j > i; j--) {
      const segment = parts.slice(i, j).join('-');
      const testPath = path.join(current, segment);
      if (fs.existsSync(testPath)) {
        current = testPath;
        i = j;
        matched = true;
        break;
      }
    }
    if (!matched) {
      current = path.join(current, parts[i]);
      i++;
    }
  }

  return current;
}

/**
 * Returns current Git repository state fingerprint to detect drift during handoff.
 */
export function getWorkspaceGitFingerprint(cwd: string): {
  commit?: string;
  branch?: string;
  isDirty?: boolean;
  diffHash?: string;
} {
  try {
    const commit = execSync('git rev-parse HEAD', { cwd, stdio: ['ignore', 'pipe', 'ignore'], encoding: 'utf8' }).trim();
    const branch = execSync('git rev-parse --abbrev-ref HEAD', { cwd, stdio: ['ignore', 'pipe', 'ignore'], encoding: 'utf8' }).trim();
    const status = execSync('git status --porcelain', { cwd, stdio: ['ignore', 'pipe', 'ignore'], encoding: 'utf8' }).trim();
    const isDirty = status.length > 0;

    let diffHash: string | undefined;
    if (isDirty) {
      const diff = execSync('git diff HEAD', { cwd, stdio: ['ignore', 'pipe', 'ignore'], encoding: 'utf8' });
      diffHash = crypto.createHash('sha256').update(diff).digest('hex').substring(0, 16);
    }

    return { commit, branch, isDirty, diffHash };
  } catch {
    return {};
  }
}

