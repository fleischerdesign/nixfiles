import { Service, type Context } from '@deepseek-ai/cordis';
import { defineTool } from '@deepseek-ai/dsh-tools';
import type { DiffCallView, DiffResultView, ToolResult } from '@deepseek-ai/dsh-tools';
import type { ApprovalService } from '@deepseek-ai/dsh-user-approval';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import { WorkspaceTransactionEngine } from './engine.js';
import type {
  ProposeMutationArgs,
  ProposeMutationResult,
  CommitTransactionArgs,
  CommitTransactionResult,
  RiskLevel
} from './types.js';

export const name = 'workspace-tx';
export const inject = ['tools', 'systemPrompt', 'approval'];

declare module '@deepseek-ai/cordis' {
  interface Context {
    workspaceTx: WorkspaceTransactionEngine;
    approval: ApprovalService;
    auth?: any;
  }
}

export function apply(ctx: Context): void {
  const engine = new WorkspaceTransactionEngine();
  ctx.provide('workspaceTx');
  ctx.workspaceTx = engine;

  ctx.systemPrompt.section({
    name: 'tool:workspace_tx',
    order: 250,
    text: [
      'Use workspace_propose_mutation to stage changes inside an isolated transaction workspace.',
      'All staged mutations are verified in a bounded execution envelope with group/user scoping.',
      'Use workspace_commit to atomically commit and fast-forward merge the verified transaction to HEAD with user approval.'
    ].join(' ')
  });

  // Tool 1: Stage Mutation inside CoW Isolation Space
  ctx.tools.register(
    defineTool({
      name: 'workspace_propose_mutation',
      description: 'Stage an atomic code or configuration modification inside an isolated transaction workspace.',
      parameters: {
        file_path: { type: 'string', required: true, description: 'Target file path relative to workspace or absolute.' },
        content: { type: 'string', required: true, description: 'Full UTF-8 content to apply.' },
        justification: { type: 'string', description: 'Technical rationale for the modification.' },
        requires_network: { type: 'boolean', description: 'Declare whether test verification requires network access.' },
        scope_type: { type: 'string', enum: ['user', 'group'], description: 'Workspace transaction scope (default: user).' },
        group: { type: 'string', description: 'Target group name if scope_type is group.' }
      },
      output: {
        schema: {
          type: 'object',
          additionalProperties: false,
          properties: {
            txId: { type: 'string', required: true },
            path: { type: 'string', required: true },
            operation: { type: 'string', required: true, enum: ['create', 'update'] },
            riskLevel: { type: 'string', required: true, enum: ['R0', 'R1', 'R2'] },
            scopeType: { type: 'string', required: true },
            scopeId: { type: 'string', required: true },
            expiresAt: { type: 'number', required: true },
            before: { oneOf: [{ type: 'string' }, { type: 'null' }] },
            after: { type: 'string', required: true }
          }
        },
        render: (_args, value: ProposeMutationResult) => [
          {
            type: 'text',
            text: `Staged ${value.operation} for ${value.path} [Risk: ${value.riskLevel}, Scope: ${value.scopeId}, Tx: ${value.txId}].`
          }
        ]
      },
      async execute(args: ProposeMutationArgs, exec): Promise<ProposeMutationResult> {
        const repoRoot = process.cwd();
        const riskLevel: RiskLevel = args.requires_network ? 'R2' : 'R1';
        const tenant = ctx.auth?.activeTenant || { username: 'local', clearance: 'Admin', groups: ['wheel'] };

        const scopeType = args.scope_type || 'user';
        let scopeId = `user:${tenant.username}`;

        if (scopeType === 'group') {
          if (!args.group) {
            throw new Error('Group scope requires a group name');
          }
          if (tenant.clearance !== 'Admin' && (!tenant.groups || !tenant.groups.includes(args.group))) {
            throw new Error(`Unauthorized: You are not a member of group "${args.group}".`);
          }
          scopeId = `group:${args.group}`;
        }

        const tx = await engine.begin(repoRoot, riskLevel, {
          scopeType,
          scopeId,
          owner: tenant.username
        });
        const targetPath = path.resolve(tx.workDir, args.file_path);

        let before: string | null = null;
        let operation: 'create' | 'update' = 'create';

        try {
          before = await fs.readFile(targetPath, 'utf8');
          operation = 'update';
        } catch {
          await fs.mkdir(path.dirname(targetPath), { recursive: true });
        }

        await fs.writeFile(targetPath, args.content, 'utf8');

        // Bounded verification run
        await engine.verify(tx.txId, {
          timeoutMs: 120000,
          allowNetwork: !!args.requires_network
        });

        return {
          txId: tx.txId,
          path: args.file_path,
          operation,
          riskLevel,
          scopeType: tx.scopeType,
          scopeId: tx.scopeId,
          expiresAt: tx.expiresAt,
          before,
          after: args.content
        };
      },
      presentCall(args: ProposeMutationArgs): DiffCallView {
        return {
          card: 'diff',
          title: `Propose ${args.file_path}`,
          diffs: [{ path: args.file_path, oldText: null, newText: args.content }],
          locations: [{ path: args.file_path }]
        };
      },
      presentResult(args: ProposeMutationArgs, result: ToolResult): DiffResultView | undefined {
        if (result.isError) return undefined;
        const diffs = (result.meta as any)?.diffs ?? [
          { path: args.file_path, oldText: null, newText: args.content }
        ];
        return { card: 'diff', title: `Proposed ${args.file_path}`, diffs };
      }
    })
  );

  // Tool 2: Human-in-the-loop Approval & OCC Atomic Commit
  ctx.tools.register(
    defineTool({
      name: 'workspace_commit',
      description: 'Commit and fast-forward merge an active, verified transaction back to the host workspace.',
      parameters: {
        tx_id: { type: 'string', required: true, description: 'ID of the active transaction to commit.' },
        commit_message: { type: 'string', required: true, description: 'Commit message describing the changes.' }
      },
      output: {
        schema: {
          type: 'object',
          additionalProperties: false,
          properties: {
            txId: { type: 'string', required: true },
            commitSha: { type: 'string', required: true },
            mergedTo: { type: 'string', required: true },
            rebased: { type: 'boolean', required: true }
          }
        },
        render: (_args, value: CommitTransactionResult) => [
          {
            type: 'text',
            text: `Transaction ${value.txId} successfully committed (${value.commitSha}) and merged to ${value.mergedTo}. Rebase applied: ${value.rebased}.`
          }
        ]
      },
      async execute(args: CommitTransactionArgs, exec): Promise<CommitTransactionResult> {
        const tx = engine.getTransaction(args.tx_id);
        if (!tx) {
          throw new Error(`Transaction ${args.tx_id} not found or already settled.`);
        }

        const tenant = ctx.auth?.activeTenant || { username: 'local', clearance: 'Admin', groups: ['wheel'] };

        // Group & User authorization for commit
        if (tenant.clearance !== 'Admin') {
          if (tx.scopeType === 'user' && tx.owner !== tenant.username) {
            throw new Error(`Unauthorized: Transaction belongs to user "${tx.owner}".`);
          }
          if (tx.scopeType === 'group') {
            const groupName = tx.scopeId.replace(/^group:/, '');
            if (!tenant.groups || !tenant.groups.includes(groupName)) {
              throw new Error(`Unauthorized: Not a member of group "${groupName}" for this transaction.`);
            }
          }
        }

        // Approval Gate via ctx.approval
        if (ctx.approval) {
          const outcome = await ctx.approval.request({
            agent: exec.agent,
            toolName: 'workspace_commit',
            reason: `Commit proposed changes: "${args.commit_message}" (Risk: ${tx.riskLevel}, Scope: ${tx.scopeId})`,
            signal: exec.signal
          });

          if (outcome !== 'allowed-once') {
            await engine.abort(args.tx_id);
            throw new Error(`Commit rejected by user approval policy: ${outcome}. Transaction aborted.`);
          }
        }

        // Execute OCC Commit with 3-Way Rebase Compensation
        return engine.commit(args.tx_id, args.commit_message);
      }
    })
  );
}
