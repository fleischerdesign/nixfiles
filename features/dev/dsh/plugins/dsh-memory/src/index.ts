import { Service, type Context } from '@deepseek-ai/cordis';
import { defineTool } from '@deepseek-ai/dsh-tools';
import * as fs from 'node:fs';
import { initializeDatabase } from './schema.js';
import { BitemporalMemoryEngine } from './engine.js';
import type {
  StoreFactArgs,
  QueryMemoryArgs,
  SecurityLabel,
  MemoryScopeType,
  EpistemicClass,
  MemoryPluginConfig,
  StaticFactDeclaration
} from './types.js';

export const name = 'memory';
export const inject = ['tools', 'systemPrompt', 'auth'];

declare module '@deepseek-ai/cordis' {
  interface Context {
    memory: BitemporalMemoryEngine;
    webServer?: any;
    auth?: any;
  }
}

export function apply(ctx: Context, config: MemoryPluginConfig = {}): void {
  const dbPath = config.dbPath || process.env.DSH_MEMORY_DB || '/var/lib/dsh/shared/knowledge.db';
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

  // Register HTTP routes for web UI when webServer is available
  ctx.inject(['webServer'], (wsCtx: any) => {
    wsCtx.webServer.register({
      kind: 'exact',
      path: '/api/memory/facts',
      handler: async (req: any, res: any) => {
        const tenant = (req as any).tenant || { username: 'local', clearance: 'Admin', groups: [] };

        if (req.method === 'GET') {
          try {
            const parsedUrl = new URL(`http://${req.headers.host || 'localhost'}${req.url}`);
            const search = parsedUrl.searchParams.get('search') || undefined;
            const scopeType = (parsedUrl.searchParams.get('scopeType') as MemoryScopeType) || undefined;
            const scopeId = parsedUrl.searchParams.get('scopeId') || undefined;
            const epistemicClass = (parsedUrl.searchParams.get('epistemicClass') as EpistemicClass) || undefined;

            const result = engine.query(
              { search, scopeType, scopeId, epistemicClass },
              tenant
            );

            res.statusCode = 200;
            res.setHeader('Content-Type', 'application/json');
            res.end(JSON.stringify({ facts: result.facts }));
          } catch (err: any) {
            res.statusCode = 500;
            res.setHeader('Content-Type', 'application/json');
            res.end(JSON.stringify({ error: err.message }));
          }
          return;
        }

        if (req.method === 'POST') {
          let body = '';
          req.on('data', (chunk: any) => { body += chunk; });
          req.on('end', async () => {
            try {
              const payload = JSON.parse(body);
              if (!payload.subject || !payload.predicate || !payload.object) {
                res.statusCode = 400;
                res.setHeader('Content-Type', 'application/json');
                res.end(JSON.stringify({ error: 'Missing required fields (subject, predicate, object)' }));
                return;
              }

              // Multi-tenant scope resolution & authorization
              const requestedScopeType: MemoryScopeType = payload.scopeType || 'user';
              let resolvedScopeId = payload.scopeId;

              if (requestedScopeType === 'user') {
                resolvedScopeId = `user:${tenant.username}`;
              } else if (requestedScopeType === 'public') {
                if (tenant.clearance !== 'Admin') {
                  res.statusCode = 403;
                  res.setHeader('Content-Type', 'application/json');
                  res.end(JSON.stringify({ error: 'Only administrators can store public memory facts' }));
                  return;
                }
                resolvedScopeId = 'public';
              } else if (requestedScopeType === 'group') {
                const groupName = (resolvedScopeId || '').replace(/^group:/, '');
                if (tenant.clearance !== 'Admin' && (!groupName || !tenant.groups?.includes(groupName))) {
                  res.statusCode = 403;
                  res.setHeader('Content-Type', 'application/json');
                  res.end(JSON.stringify({ error: `Not a member of group "${groupName}"` }));
                  return;
                }
                resolvedScopeId = `group:${groupName}`;
              }

              const fact = engine.storeFact({
                subject: payload.subject,
                predicate: payload.predicate,
                object: payload.object,
                validFrom: payload.validFrom ?? Date.now(),
                validTo: payload.validTo ?? Infinity,
                typeConstraint: payload.typeConstraint ?? 'String',
                confidence: payload.confidence ?? 1.0,
                securityLabel: payload.securityLabel ?? 'user',
                ttlSeconds: payload.ttlSeconds,
                scopeType: requestedScopeType,
                scopeId: resolvedScopeId,
                author: tenant.username,
                epistemicClass: payload.epistemicClass ?? 'evidence'
              });

              res.statusCode = 201;
              res.setHeader('Content-Type', 'application/json');
              res.end(JSON.stringify({ fact }));
            } catch (err: any) {
              res.statusCode = 400;
              res.setHeader('Content-Type', 'application/json');
              res.end(JSON.stringify({ error: err.message }));
            }
          });
          return;
        }

        if (req.method === 'DELETE') {
          const parsedUrl = new URL(`http://${req.headers.host || 'localhost'}${req.url}`);
          const id = parsedUrl.searchParams.get('id');

          if (!id) {
            res.statusCode = 400;
            res.setHeader('Content-Type', 'application/json');
            res.end(JSON.stringify({ error: 'Missing id query parameter' }));
            return;
          }

          try {
            engine.retractFact(id, tenant);
            res.statusCode = 200;
            res.setHeader('Content-Type', 'application/json');
            res.end(JSON.stringify({ success: true, retracted: id }));
          } catch (err: any) {
            res.statusCode = err.message.includes('Unauthorized') ? 403 : 400;
            res.setHeader('Content-Type', 'application/json');
            res.end(JSON.stringify({ error: err.message }));
          }
          return;
        }

        res.statusCode = 405;
        res.setHeader('Content-Type', 'application/json');
        res.end(JSON.stringify({ error: 'Method Not Allowed' }));
      }
    });
  });

  // Ingest declarative static facts from configuration (Agnostic Ingestion) - Class 1: Axioms!
  const factsToIngest: StaticFactDeclaration[] = [...(config.facts || [])];

  if (config.factsFile && fs.existsSync(config.factsFile)) {
    try {
      const content = fs.readFileSync(config.factsFile, 'utf8');
      const parsed = JSON.parse(content);
      if (Array.isArray(parsed)) {
        factsToIngest.push(...parsed);
      }
    } catch {
      // Non-fatal: continue if external facts file cannot be parsed
    }
  }

  for (const item of factsToIngest) {
    if (item.subject && item.predicate && item.object) {
      engine.storeFact({
        subject: item.subject,
        predicate: item.predicate,
        object: item.object,
        validFrom: 0, // Axiom: valid from epoch start
        validTo: Infinity, // Axiom: immutable, never expires
        typeConstraint: item.type_constraint ?? 'String',
        confidence: item.confidence ?? 1.0,
        securityLabel: item.security_label ?? 'system',
        scopeType: item.scope_type ?? 'public',
        scopeId: item.scope_id ?? 'public',
        author: 'system',
        epistemicClass: 'axiom' // Tagged as Class 1 Axiom
      });
    }
  }

  // System Prompt Section: Knowledge instructions
  ctx.systemPrompt.section({
    name: 'tool:memory',
    order: 260,
    text: [
      'Use memory_query to retrieve verified infrastructure facts, host parameters, and dependency graphs.',
      'Use memory_store to persist verified empirical architectural decisions and constraints (Class 2 Evidence).'
    ].join(' ')
  });

  // Token-Guarded Context Recall Gate
  if (config.autoConsolidate !== false) {
    ctx.inject(['llm'], (llmCtx: any) => {
      llmCtx.llm.on('llm/pre-request', async (request: any, next: () => Promise<any>) => {
        try {
          const authService = ctx.get('auth');
          const tenant = authService?.activeTenant || { username: 'local', clearance: 'Admin', groups: [] };
          const messages = request?.messages || [];
          const lastUserMessage = [...messages].reverse().find((m: any) => m.role === 'user');

          if (lastUserMessage && typeof lastUserMessage.content === 'string') {
            // Extract recent turn texts for deduplication
            const recentTurnTexts = messages.slice(-4).map((m: any) => typeof m.content === 'string' ? m.content : '');

            const recalled = engine.recallContextGuarded({
              queryText: lastUserMessage.content,
              identity: tenant,
              recentTurnTexts,
              maxTokens: config.maxRecallTokens ?? 150,
              minThreshold: config.minRecallThreshold ?? -1.5
            });

            if (recalled.length > 0) {
              const memoryLines = recalled.map(f => `- ${f.subject} ${f.predicate} ${f.object} [${f.epistemicClass || 'evidence'}] (${f.scopeId})`).join('\n');
              const memoryContextBlock = `\n[Recalled Knowledge Memories]:\n${memoryLines}\n`;

              if (request.messages && request.messages.length > 0 && request.messages[0].role === 'system') {
                request.messages[0].content += memoryContextBlock;
              }
            }
          }
        } catch {
          // Non-fatal: continue model invocation if recall context fails
        }
        return next();
      });
    });
  }

  // Tool 1: Deductive & Bitemporal Query
  ctx.tools.register(
    defineTool({
      name: 'memory_query',
      description: 'Query verified infrastructure facts, bitemporal historical states, or recursive dependency closures.',
      parameters: {
        subject: { type: 'string', description: 'Subject entity URI (e.g. "urn:nix:host:strummer").' },
        predicate: { type: 'string', description: 'Predicate relation (e.g. "sys:bindsPort" or "infra:dependsOn").' },
        as_of_time: { type: 'number', description: 'Historical timestamp for time-travel queries (defaults to now).' },
        recursive_closure: { type: 'boolean', description: 'Whether to compute recursive transitive closure (Datalog fixpoint).' },
        scope_type: { type: 'string', enum: ['public', 'group', 'user', 'repo'], description: 'Filter facts by memory scope.' },
        scope_id: { type: 'string', description: 'Filter facts by scope ID (e.g. "user:name" or "group:dev").' },
        epistemic_class: { type: 'string', enum: ['axiom', 'evidence', 'hypothesis'], description: 'Filter by epistemic class.' },
        search: { type: 'string', description: 'Full-text search keyword query across facts.' }
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
      async execute(args: QueryMemoryArgs & { scope_type?: MemoryScopeType; scope_id?: string; epistemic_class?: EpistemicClass; search?: string }): Promise<any> {
        if (args.recursive_closure && args.subject && args.predicate) {
          const transitive = engine.queryTransitiveClosure(args.subject, args.predicate);
          return { facts: [], transitive };
        }

        const authService = ctx.get('auth');
        const tenant = authService?.activeTenant || { username: 'local', clearance: 'Admin', groups: [] };

        const result = engine.query({
          subject: args.subject,
          predicate: args.predicate,
          asOfValid: args.as_of_time,
          scopeType: args.scope_type,
          scopeId: args.scope_id,
          epistemicClass: args.epistemic_class,
          search: args.search
        }, tenant);

        // Sanitize to lossless JSON (converts Infinity timestamps to null and removes undefined)
        const sanitized = JSON.parse(JSON.stringify({
          facts: result.facts,
          transitive: []
        }));

        return sanitized;
      }
    })
  );

  // Tool 2: Fact Ingestion with Epistemic Protection & Belief Revision
  ctx.tools.register(
    defineTool({
      name: 'memory_store',
      description: 'Store a verified system fact or architectural constraint into bitemporal memory (Class 2 Evidence or Class 3 Hypothesis).',
      parameters: {
        subject: { type: 'string', required: true, description: 'Subject entity URI (e.g. "urn:nix:host:strummer").' },
        predicate: { type: 'string', required: true, description: 'Predicate relation (e.g. "nix:hasOption").' },
        object: { type: 'string', required: true, description: 'Target entity URI or typed value.' },
        type_constraint: { type: 'string', description: 'Type constraint (String, CIDR, Port, etc.).' },
        confidence: { type: 'number', description: 'Epistemic confidence between 0.0 and 1.0 (default: 1.0).' },
        security_label: { type: 'string', enum: ['system', 'operator', 'user'], description: 'Lattice security classification.' },
        ttl_seconds: { type: 'number', description: 'Optional time-to-live in seconds for ephemeral facts.' },
        scope_type: { type: 'string', enum: ['public', 'group', 'user', 'repo'], description: 'Memory scope tier (default: user).' },
        scope_id: { type: 'string', description: 'Identifier of the target scope (e.g. group name or repo ID).' },
        epistemic_class: { type: 'string', enum: ['evidence', 'hypothesis'], description: 'Epistemic class (evidence = verified fact, hypothesis = unconfirmed assumption).' }
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
        const authService = ctx.get('auth');
        const tenant = authService?.activeTenant || { username: 'local', clearance: 'Admin', groups: [] };

        const requestedScopeType: MemoryScopeType = args.scope_type || 'user';
        let resolvedScopeId = args.scope_id;

        if (requestedScopeType === 'user') {
          resolvedScopeId = `user:${tenant.username}`;
        } else if (requestedScopeType === 'public') {
          if (tenant.clearance !== 'Admin') {
            throw new Error('PermissionDenied: Only administrators can store public memory facts.');
          }
          resolvedScopeId = 'public';
        } else if (requestedScopeType === 'group') {
          const groupName = (resolvedScopeId || '').replace(/^group:/, '');
          if (tenant.clearance !== 'Admin' && (!groupName || !tenant.groups?.includes(groupName))) {
            throw new Error(`PermissionDenied: Not a member of group "${groupName}".`);
          }
          resolvedScopeId = `group:${groupName}`;
        }

        // Tools cannot store Class 1 Axioms (only declarative NixOS can do that)
        const targetClass: EpistemicClass = args.epistemic_class === 'hypothesis' ? 'hypothesis' : 'evidence';

        const fact = engine.storeFact({
          subject: args.subject,
          predicate: args.predicate,
          object: args.object,
          validFrom: args.valid_from ?? Date.now(),
          validTo: args.valid_to ?? Infinity,
          typeConstraint: args.type_constraint ?? 'String',
          confidence: args.confidence ?? 1.0,
          securityLabel: args.security_label ?? 'user',
          ttlSeconds: args.ttl_seconds,
          scopeType: requestedScopeType,
          scopeId: resolvedScopeId,
          author: tenant.username,
          epistemicClass: targetClass
        });

        return {
          id: fact.id,
          status: fact.status,
          epistemic_class: fact.epistemicClass
        };
      }
    })
  );
}
