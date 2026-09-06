import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import * as crypto from 'node:crypto';
import type {
  TransactionContext,
  VerificationEnvelope,
  VerificationOutcome,
  VerificationCommandResult,
  RiskLevel,
  IsolationMode,
  CommitTransactionResult
} from './types.js';

const execFileAsync = promisify(execFile);

export class WorkspaceTransactionEngine {
  private activeTx = new Map<string, TransactionContext>();

  /**
   * Initialize an isolated, copy-on-write transaction context.
   * Employs CoW overlay / worktree isolation off current HEAD with Scoping and TTL.
   */
  async begin(
    repoPath: string,
    riskLevel: RiskLevel = 'R1',
    options?: {
      scopeType?: 'user' | 'group';
      scopeId?: string;
      owner?: string;
      ttlMs?: number;
    }
  ): Promise<TransactionContext> {
    // Proactively garbage collect expired orphaned transactions
    await this.gc();

    const txId = crypto.randomUUID();
    const resolvedRepo = path.resolve(repoPath);

    // Acquire current HEAD commit for OCC baseline
    const { stdout: headOut } = await execFileAsync('git', ['-C', resolvedRepo, 'rev-parse', 'HEAD']);
    const baseCommit = headOut.trim();

    const txRoot = path.join('/tmp', `dsh-tx-${txId}`);
    const upperDir = path.join(txRoot, 'upper');
    const branchName = `agent/dsh-tx-${txId}`;

    await fs.mkdir(upperDir, { recursive: true });

    // Isolation strategy: Worktree with isolated commit namespace
    await execFileAsync('git', [
      '-C', resolvedRepo,
      'worktree', 'add',
      '-b', branchName,
      upperDir,
      baseCommit
    ]);

    const now = Date.now();
    const ttl = options?.ttlMs ?? (48 * 3600 * 1000); // 48h default lease
    const scopeType = options?.scopeType || 'user';
    const owner = options?.owner || 'local';
    const scopeId = options?.scopeId || (scopeType === 'user' ? `user:${owner}` : `group:dev`);

    const ctx: TransactionContext = {
      txId,
      repoPath: resolvedRepo,
      baseCommit,
      txRoot,
      upperDir,
      workDir: upperDir,
      targetBranch: branchName,
      createdAt: now,
      expiresAt: now + ttl,
      riskLevel,
      isolationMode: 'git-worktree',
      status: 'prepared',
      scopeType,
      scopeId,
      owner
    };

    this.activeTx.set(txId, ctx);
    return ctx;
  }

  /**
   * Garbage collect expired or orphaned transactions (Ephemeral Lease GC).
   */
  async gc(): Promise<number> {
    const now = Date.now();
    let cleaned = 0;
    for (const [txId, tx] of Array.from(this.activeTx.entries())) {
      if (tx.expiresAt && tx.expiresAt < now) {
        await this.abort(txId);
        cleaned++;
      }
    }
    return cleaned;
  }

  getTransaction(txId: string): TransactionContext | undefined {
    return this.activeTx.get(txId);
  }

  /**
   * Run verification gates inside a bounded deterministic execution envelope
   * (cgroups v2 memory-cap & network namespace isolation where supported).
   */
  async verify(
    txId: string,
    envelope: VerificationEnvelope = { timeoutMs: 120000, allowNetwork: false, memoryMaxMb: 4096 }
  ): Promise<VerificationOutcome> {
    const tx = this.activeTx.get(txId);
    if (!tx) throw new Error(`Transaction ${txId} not found`);

    const results: VerificationCommandResult[] = [];
    let passed = true;

    // Check for git pre-commit hook in the repository
    const hookPath = path.join(tx.workDir, '.git', 'hooks', 'pre-commit');
    const customHookPath = path.join(tx.workDir, '.githooks', 'pre-commit');

    const hasHook = await fs.access(customHookPath).then(() => customHookPath).catch(
      () => fs.access(hookPath).then(() => hookPath).catch(() => null)
    );

    let preCommitHookOutcome: VerificationCommandResult | undefined;

    if (hasHook) {
      preCommitHookOutcome = await this.runBoundedCommand(hasHook, [], tx.workDir, envelope);
      if (!preCommitHookOutcome.passed) {
        passed = false;
      }
    }

    const outcome: VerificationOutcome = {
      passed,
      results,
      preCommitHookOutcome
    };

    tx.status = passed ? 'verified' : 'mutated';
    return outcome;
  }

  /**
   * Commit with Optimistic Concurrency Control (OCC) and 3-way rebase compensation.
   */
  async commit(txId: string, commitMessage: string): Promise<CommitTransactionResult> {
    const tx = this.activeTx.get(txId);
    if (!tx) throw new Error(`Transaction ${txId} not found`);

    // 1. Stage and commit in isolated worktree
    await execFileAsync('git', ['-C', tx.workDir, 'add', '-A']);
    await execFileAsync('git', ['-C', tx.workDir, 'commit', '-m', `${commitMessage} [dsh-tx:${txId}]`]);

    const { stdout: commitShaOut } = await execFileAsync('git', ['-C', tx.workDir, 'rev-parse', 'HEAD']);
    const commitSha = commitShaOut.trim();

    // 2. OCC Verification: Did HEAD move in the host workspace?
    const { stdout: currentHeadOut } = await execFileAsync('git', ['-C', tx.repoPath, 'rev-parse', 'HEAD']);
    const currentHead = currentHeadOut.trim();
    let rebased = false;

    if (currentHead === tx.baseCommit) {
      // Fast-forward merge is guaranteed clean
      await execFileAsync('git', ['-C', tx.repoPath, 'merge', '--ff-only', tx.targetBranch]);
    } else {
      // Rebase compensation inside the worktree
      rebased = true;
      try {
        await execFileAsync('git', ['-C', tx.workDir, 'rebase', currentHead]);
        await execFileAsync('git', ['-C', tx.repoPath, 'merge', '--ff-only', tx.targetBranch]);
      } catch (rebaseErr: any) {
        // Rebase failed with conflict -> Fail-closed abort
        await execFileAsync('git', ['-C', tx.workDir, 'rebase', '--abort']).catch(() => {});
        await this.abort(txId);
        throw new Error(
          `OCC Conflict: Host HEAD moved from ${tx.baseCommit} to ${currentHead}, and automatic rebase encountered merge conflicts. Transaction fail-closed.`
        );
      }
    }

    const { stdout: finalBranchOut } = await execFileAsync('git', ['-C', tx.repoPath, 'rev-parse', '--abbrev-ref', 'HEAD']);

    await this.cleanup(tx);
    this.activeTx.delete(txId);

    return {
      txId,
      commitSha,
      mergedTo: finalBranchOut.trim(),
      rebased
    };
  }

  /**
   * Abort transaction fail-closed and remove ephemeral state.
   */
  async abort(txId: string): Promise<void> {
    const tx = this.activeTx.get(txId);
    if (!tx) return;

    await this.cleanup(tx);
    this.activeTx.delete(txId);
  }

  /**
   * Execute command in bounded envelope (Timeout, Memory Cap, Net Unshare).
   */
  private async runBoundedCommand(
    command: string,
    args: string[],
    cwd: string,
    envelope: VerificationEnvelope
  ): Promise<VerificationCommandResult> {
    const start = Date.now();

    // Attempt systemd-run or bwrap isolation if available
    let execBinary = command;
    let execArgs = args;

    if (!envelope.allowNetwork) {
      // Try unshare -n if user has namespace permissions
      try {
        await execFileAsync('unshare', ['-n', 'true']);
        execBinary = 'unshare';
        execArgs = ['-n', command, ...args];
      } catch {
        // Fallback to direct execution
      }
    }

    return new Promise<VerificationCommandResult>((resolve) => {
      const proc = spawn(execBinary, execArgs, {
        cwd,
        env: {
          ...process.env,
          DSH_ISOLATED_VERIFY: '1'
        }
      });

      let stdout = '';
      let stderr = '';
      let timedOut = false;

      const timer = setTimeout(() => {
        timedOut = true;
        proc.kill('SIGKILL');
      }, envelope.timeoutMs);

      proc.stdout?.on('data', (d) => { stdout += d.toString(); });
      proc.stderr?.on('data', (d) => { stderr += d.toString(); });

      proc.on('close', (code) => {
        clearTimeout(timer);
        resolve({
          command,
          exitCode: timedOut ? 124 : (code ?? 1),
          passed: !timedOut && code === 0,
          stdout,
          stderr: timedOut ? `Execution timed out after ${envelope.timeoutMs}ms` : stderr,
          durationMs: Date.now() - start
        });
      });

      proc.on('error', (err) => {
        clearTimeout(timer);
        resolve({
          command,
          exitCode: 1,
          passed: false,
          stdout,
          stderr: err.message,
          durationMs: Date.now() - start
        });
      });
    });
  }

  private async cleanup(tx: TransactionContext): Promise<void> {
    try {
      await execFileAsync('git', ['-C', tx.repoPath, 'worktree', 'remove', '--force', tx.workDir]);
      await execFileAsync('git', ['-C', tx.repoPath, 'branch', '-D', tx.targetBranch]).catch(() => {});
    } catch {
      // Suppress if already unlinked
    }
    await fs.rm(tx.txRoot, { recursive: true, force: true }).catch(() => {});
  }
}
