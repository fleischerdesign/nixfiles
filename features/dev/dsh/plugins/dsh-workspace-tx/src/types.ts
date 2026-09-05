/**
 * @module @dsh/workspace-tx/types
 * Formal types for Optimistic Concurrency Control (OCC), hermetic CoW isolation,
 * risk lattices, and bounded execution envelopes.
 */

export type RiskLevel = 'R0' | 'R1' | 'R2';

export type IsolationMode = 'cow-overlay' | 'git-worktree';

export interface VerificationEnvelope {
  timeoutMs: number;
  memoryMaxMb?: number;
  allowNetwork: boolean;
}

export interface VerificationCommandResult {
  command: string;
  exitCode: number;
  passed: boolean;
  stdout: string;
  stderr: string;
  durationMs: number;
}

export interface VerificationOutcome {
  passed: boolean;
  results: VerificationCommandResult[];
  preCommitHookOutcome?: VerificationCommandResult;
}

export interface TransactionContext {
  txId: string;
  repoPath: string;
  baseCommit: string;
  txRoot: string;
  upperDir: string;
  workDir: string;
  targetBranch: string;
  createdAt: number;
  riskLevel: RiskLevel;
  isolationMode: IsolationMode;
  status: 'prepared' | 'mutated' | 'verified' | 'committed' | 'aborted';
}

export interface ProposeMutationArgs {
  file_path: string;
  content: string;
  justification?: string;
  requires_network?: boolean;
}

export interface ProposeMutationResult {
  txId: string;
  path: string;
  operation: 'create' | 'update';
  riskLevel: RiskLevel;
  before: string | null;
  after: string;
}

export interface CommitTransactionArgs {
  tx_id: string;
  commit_message: string;
}

export interface CommitTransactionResult {
  txId: string;
  commitSha: string;
  mergedTo: string;
  rebased: boolean;
}
