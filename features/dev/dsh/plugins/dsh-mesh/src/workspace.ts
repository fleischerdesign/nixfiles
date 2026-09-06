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

/**
 * Synchronizes a workspace locally onto the current host.
 * If the workspace is a Git repository, it either clones it into ~/dev/<repo>
 * or fast-forwards an existing local checkout.
 */
export function syncWorkspaceLocally(
  workspaceUrn: string,
  preferredParentDir?: string,
  peerEndpoint?: string
): { success: boolean; localPath: string; message: string } {
  const home = process.env.HOME || '/root';
  const defaultBaseDir = preferredParentDir || path.join(home, 'dev');

  if (!fs.existsSync(defaultBaseDir)) {
    try {
      fs.mkdirSync(defaultBaseDir, { recursive: true });
    } catch (e: any) {
      return { success: false, localPath: '', message: `Failed to create directory ${defaultBaseDir}: ${e.message}` };
    }
  }

  // 1. Git Repository URN
  if (workspaceUrn.startsWith('urn:dsh:workspace:git:')) {
    const rawRepo = workspaceUrn.replace('urn:dsh:workspace:git:', '');
    const [repoPath] = rawRepo.split(':');
    const repoName = path.basename(repoPath);
    const targetDir = path.join(defaultBaseDir, repoName);
    const cloneUrl = `https://${repoPath}`;

    if (fs.existsSync(targetDir)) {
      try {
        const isGit = fs.existsSync(path.join(targetDir, '.git'));
        if (!isGit) {
          return {
            success: false,
            localPath: targetDir,
            message: `Target path "${targetDir}" already exists but is not a git repository.`
          };
        }

        const out = execSync('git pull --ff-only', {
          cwd: targetDir,
          stdio: ['ignore', 'pipe', 'pipe'],
          encoding: 'utf8',
          timeout: 15000
        });

        return {
          success: true,
          localPath: targetDir,
          message: `Workspace "${repoName}" updated: ${out.trim() || 'Already up to date.'}`
        };
      } catch (err: any) {
        return {
          success: false,
          localPath: targetDir,
          message: `Git pull failed in "${targetDir}": ${err.stderr || err.message}`
        };
      }
    } else {
      try {
        execSync(`git clone "${cloneUrl}" "${targetDir}"`, {
          stdio: ['ignore', 'pipe', 'pipe'],
          encoding: 'utf8',
          timeout: 60000
        });

        return {
          success: true,
          localPath: targetDir,
          message: `Repository "${repoName}" successfully cloned to "${targetDir}".`
        };
      } catch (err: any) {
        return {
          success: false,
          localPath: targetDir,
          message: `Git clone failed from "${cloneUrl}": ${err.stderr || err.message}`
        };
      }
    }
  }

  // 2. Non-Git Home-Relative Workspace URN
  if (workspaceUrn.startsWith('urn:dsh:workspace:relhome:')) {
    const relPath = workspaceUrn.replace('urn:dsh:workspace:relhome:', '');
    const targetDir = path.resolve(home, relPath);

    // Prevent path traversal
    if (!targetDir.startsWith(home)) {
      return {
        success: false,
        localPath: '',
        message: `Security violation: Path "${relPath}" resolves outside user home directory.`
      };
    }

    if (!peerEndpoint) {
      return {
        success: false,
        localPath: targetDir,
        message: `Direct peer sync requires peerEndpoint to stream workspace archive.`
      };
    }

    try {
      const url = peerEndpoint.startsWith('http') ? peerEndpoint : `http://${peerEndpoint}`;
      const exportUrl = `${url}/mesh/workspace/archive?path=${encodeURIComponent(relPath)}`;

      const parentDir = path.dirname(targetDir);
      if (!fs.existsSync(parentDir)) {
        fs.mkdirSync(parentDir, { recursive: true });
      }

      // Stage in temporary directory for atomic extract
      const tmpDir = `${targetDir}.sync-${Date.now()}`;
      fs.mkdirSync(tmpDir, { recursive: true });

      try {
        // Stream directly from peer into tar | zstd -d
        execSync(`curl -fsSL "${exportUrl}" | zstd -dc | tar -xf - -C "${tmpDir}"`, {
          stdio: ['ignore', 'pipe', 'pipe'],
          timeout: 120000
        });

        // Backup existing destination if present
        if (fs.existsSync(targetDir)) {
          const backupDir = `${targetDir}.bak-${Date.now()}`;
          fs.renameSync(targetDir, backupDir);
        }

        fs.renameSync(tmpDir, targetDir);

        return {
          success: true,
          localPath: targetDir,
          message: `Workspace "${path.basename(targetDir)}" successfully synchronized from peer.`
        };
      } catch (err: any) {
        if (fs.existsSync(tmpDir)) {
          fs.rmSync(tmpDir, { recursive: true, force: true });
        }
        return {
          success: false,
          localPath: targetDir,
          message: `Non-git archive transfer failed from "${exportUrl}": ${err.stderr || err.message}`
        };
      }
    } catch (e: any) {
      return {
        success: false,
        localPath: targetDir,
        message: `Workspace sync error: ${e.message}`
      };
    }
  }

  return {
    success: false,
    localPath: '',
    message: `Unsupported workspace URN format: "${workspaceUrn}".`
  };
}

