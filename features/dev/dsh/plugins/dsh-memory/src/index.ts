import { Service, type Context } from '@deepseek-ai/cordis';
import { defineTool } from '@deepseek-ai/dsh-tools';
import * as path from 'node:path';
import { initializeDatabase } from './schema.js';
import { BitemporalMemoryEngine } from './engine.js';
import type { StoreFactArgs, QueryMemoryArgs, SecurityLabel } from './types.js';

export const name = 'memory';
export const inject = ['tools', 'systemPrompt'];

declare module '@deepseek-ai/cordis' {
  interface Context {
    memory: BitemporalMemoryEngine;
  }
}

export function apply(ctx: Context): void {
  // Use persistent path in /var/lib/dsh or in-memory fallback
  const dbPath = process.env.DSH_MEMORY_DB || '/var/lib/dsh/shared/knowledge.db';
  let db;

  try {
    db = initializeDatabase(dbPath);
  } catch {
    // Fallback to in-memory for non-root / unprivileged runs
    db = initializeDatabase(':memory:');
  }

  const engine = new BitemporalMemoryEngine(db);
  ctx.provide('memory');
  ctx.memory = engine;

  ctx.systemPrompt.section({
    name: 'tool:memory',
    order: 260,
    text: [
      'Use memory_query to retrieve verified infrastructure facts, host parameters, and dependency graphs.',
      'Use memory_store to persist invariant knowledge, architectural decisions, and observed system constraints.'
    ].join(' ')
  });

  // Tool 1: Deductive & Bitemporal Query
  ctx.tools.register(
    defineTool({
      name: 'memory_query',
      description: 'Query verified infrastructure facts, bitemporal historical states, or recursive dependency closures.',
      parameters: {
        subject: { type: 'string', description: 'Subject entity URI (e.g. "urn:nix:host:strummer").' },
        predicate: { type: 'string', description: 'Predicate relation (e.g. "sys:bindsPort" or "infra:dependsOn").' },
        as_of_time: { type: 'number', description: 'Historical timestamp for time-travel queries (defaults to now).' },
        recursive_closure: { type: 'boolean', description: 'Whether to compute recursive transitive closure (Datalog fixpoint).' }
      },
      output: {
        schema: {
          type: 'object',
          additionalProperties: true,
          properties: {
            facts: { type: 'array' },
            transitive: { type: 'array' }
          }
        },
        render: (_args, value: any) => [
          {
            type: 'text',
            text: `<memory_results facts="${value.facts?.length ?? 0}" transitive="${value.transitive?.length ?? 0}">\n${JSON.stringify(value, null, 2)}\n</memory_results>`
          }
        ]
      },
      async execute(args: QueryMemoryArgs): Promise<any> {
        if (args.recursive_closure && args.subject && args.predicate) {
          const transitive = engine.queryTransitiveClosure(args.subject, args.predicate);
          return { facts: [], transitive };
        }

        const result = engine.query({
          subject: args.subject,
          predicate: args.predicate,
          asOfValid: args.as_of_time
        });

        return {
          facts: result.facts,
          transitive: []
        };
      }
    })
  );

  // Tool 2: Fact Ingestion with Belief Revision
  ctx.tools.register(
    defineTool({
      name: 'memory_store',
      description: 'Store a verified system fact or architectural constraint into bitemporal memory.',
      parameters: {
        subject: { type: 'string', required: true, description: 'Subject entity URI (e.g. "urn:nix:host:strummer").' },
        predicate: { type: 'string', required: true, description: 'Predicate relation (e.g. "nix:hasOption").' },
        object: { type: 'string', required: true, description: 'Target entity URI or typed value.' },
        type_constraint: { type: 'string', description: 'Type constraint (String, CIDR, Port, etc.).' },
        confidence: { type: 'number', description: 'Epistemic confidence between 0.0 and 1.0 (default: 1.0).' },
        security_label: { type: 'string', enum: ['system', 'operator', 'user'], description: 'Lattice security classification.' }
      },
      output: {
        schema: {
          type: 'object',
          additionalProperties: true,
          properties: {
            id: { type: 'string', required: true },
            status: { type: 'string', required: true }
          }
        },
        render: (_args, value: any) => [
          {
            type: 'text',
            text: `Stored fact ${value.id} [status: ${value.status}].`
          }
        ]
      },
      async execute(args: StoreFactArgs): Promise<any> {
        const fact = engine.storeFact({
          subject: args.subject,
          predicate: args.predicate,
          object: args.object,
          validFrom: args.valid_from ?? Date.now(),
          validTo: args.valid_to ?? Infinity,
          typeConstraint: args.type_constraint ?? 'String',
          confidence: args.confidence ?? 1.0,
          securityLabel: args.security_label ?? 'system'
        });

        return {
          id: fact.id,
          status: fact.status
        };
      }
    })
  );
}

export default apply;
