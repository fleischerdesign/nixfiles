import { Service, type Context } from '@deepseek-ai/cordis';
import { defineTool } from '@deepseek-ai/dsh-tools';
import * as http from 'node:http';
import { MeshTransportClient } from './protocol.js';
import type {
  MeshPluginConfig,
  PeerStatus,
  HeartbeatPayload,
  SyncDeltaRequest,
  SyncDeltaResponse
} from './types.js';

export const name = 'mesh';
export const inject = ['tools', 'systemPrompt'];

declare module '@deepseek-ai/cordis' {
  interface Context {
    mesh: MeshCoordinatorService;
  }
}

export class MeshCoordinatorService extends Service {
  private peers = new Map<string, PeerStatus>();
  private client: MeshTransportClient;
  private server?: http.Server;
  private heartbeatTimer?: NodeJS.Timeout;

  constructor(ctx: Context, private config: MeshPluginConfig) {
    super(ctx, 'mesh');
    this.client = new MeshTransportClient(5000);

    for (const peer of config.peers || []) {
      this.peers.set(peer.id, {
        id: peer.id,
        endpoint: peer.endpoint,
        lastHeartbeatMs: 0,
        rttMs: -1,
        healthy: false,
        maxTxSeen: 0
      });
    }

    if (config.listenPort) {
      this.startServer(config.listenPort, config.listenHost || '0.0.0.0');
    }

    this.startHeartbeatLoop(config.heartbeatIntervalMs || 10000);
  }

  getPeers(): PeerStatus[] {
    return Array.from(this.peers.values());
  }

  async dispatchTask(peerId: string, toolName: string, args: Record<string, any>): Promise<any> {
    const peer = this.peers.get(peerId);
    if (!peer) {
      throw new Error(`Target peer node "${peerId}" not found in mesh registry.`);
    }

    const taskId = `tx-${Date.now()}-${Math.random().toString(36).substring(2, 7)}`;
    return this.client.executeRemoteTask(peer.endpoint, {
      fromNodeId: this.config.nodeId,
      taskId,
      toolName,
      arguments: args,
      timestamp: Date.now()
    });
  }

  private startServer(port: number, host: string): void {
    this.server = http.createServer((req, res) => {
      if (req.method !== 'POST') {
        res.writeHead(405);
        res.end();
        return;
      }

      let body = '';
      req.on('data', (d) => { body += d; });
      req.on('end', () => {
        try {
          const parsed = JSON.parse(body);

          if (req.url === '/mesh/heartbeat') {
            const resp: HeartbeatPayload = {
              nodeId: this.config.nodeId,
              timestamp: Date.now(),
              maxTx: Date.now()
            };
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify(resp));
          } else if (req.url === '/mesh/sync') {
            // Delta response for CvRDT merge
            const resp: SyncDeltaResponse = {
              fromNodeId: this.config.nodeId,
              facts: [],
              maxTx: Date.now()
            };
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify(resp));
          } else if (req.url === '/mesh/task') {
            // Remote tool execution request under MTAA Task Contract
            void (async () => {
              try {
                const taskReq = parsed;
                const toolName = taskReq.toolName;
                const toolArgs = taskReq.arguments || {};

                // Execute tool via Cordis tools service
                if (this.ctx.tools) {
                  const out = await this.ctx.tools.execute({
                    callId: `remote-${taskReq.taskId}` as any,
                    name: toolName,
                    arguments: toolArgs,
                    signal: new AbortController().signal
                  });

                  res.writeHead(200, { 'Content-Type': 'application/json' });
                  res.end(JSON.stringify({
                    fromNodeId: this.config.nodeId,
                    taskId: taskReq.taskId,
                    success: !out.isError,
                    result: out.value || out.content,
                    error: out.error?.message,
                    executedAt: Date.now()
                  }));
                } else {
                  res.writeHead(503, { 'Content-Type': 'application/json' });
                  res.end(JSON.stringify({ error: 'Tools service unavailable on target node' }));
                }
              } catch (e: any) {
                res.writeHead(500, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ error: e.message || String(e) }));
              }
            })();
          } else {
            res.writeHead(404);
            res.end();
          }
        } catch {
          res.writeHead(400);
          res.end();
        }
      });
    });

    this.server.listen(port, host);
  }

  private startHeartbeatLoop(intervalMs: number): void {
    this.heartbeatTimer = setInterval(() => {
      this.pollPeers();
    }, intervalMs);
  }

  private async pollPeers(): Promise<void> {
    for (const [id, peer] of this.peers.entries()) {
      try {
        const { rttMs, response } = await this.client.sendHeartbeat(peer.endpoint, {
          nodeId: this.config.nodeId,
          timestamp: Date.now(),
          maxTx: Date.now()
        });

        peer.lastHeartbeatMs = Date.now();
        peer.rttMs = rttMs;
        peer.healthy = true;
        peer.maxTxSeen = response.maxTx;
      } catch {
        peer.healthy = false;
        peer.rttMs = -1;
      }
    }
  }

  close(): void {
    if (this.heartbeatTimer) clearInterval(this.heartbeatTimer);
    this.server?.close();
  }
}

export function apply(ctx: Context, config: MeshPluginConfig): void {
  const service = new MeshCoordinatorService(ctx, config || { nodeId: 'standalone' });
  ctx.mesh = service;

  ctx.effect(() => {
    return () => {
      service.close();
    };
  });

  ctx.systemPrompt.section({
    name: 'tool:mesh',
    order: 270,
    text: 'Use mesh_peers to inspect cluster health, roundtrip latencies, and distributed synchronization across peer nodes.'
  });

  ctx.tools.register(
    defineTool({
      name: 'mesh_peers',
      description: 'List connected cluster peer nodes, health status, and roundtrip latencies.',
      parameters: {},
      output: {
        schema: {
          type: 'object',
          additionalProperties: true,
          properties: {
            nodeId: { type: 'string' },
            peers: { type: 'array' }
          }
        },
        render: (_args, value: any) => [
          {
            type: 'text',
            text: `<mesh_status local_node="${value.nodeId}">\n${JSON.stringify(value.peers, null, 2)}\n</mesh_status>`
          }
        ]
      },
      async execute(): Promise<any> {
        return {
          nodeId: config.nodeId || 'unknown',
          peers: service.getPeers()
        };
      }
    })
  );

  // Tool: Remote Task Dispatching under MTAA Contract
  ctx.tools.register(
    defineTool({
      name: 'mesh_dispatch',
      description: 'Dispatch an atomic tool call to be executed on a remote peer node in the cluster mesh.',
      parameters: {
        peer_id: { type: 'string', required: true, description: 'Hostname / ID of target peer node (e.g. mackaye, rollins, strummer).' },
        tool_name: { type: 'string', required: true, description: 'Target tool to invoke remotely.' },
        arguments: { type: 'object', additionalProperties: true, description: 'Arguments payload for the remote tool.' }
      },
      output: {
        schema: {
          type: 'object',
          additionalProperties: true,
          properties: {
            fromNodeId: { type: 'string' },
            taskId: { type: 'string' },
            success: { type: 'boolean' }
          }
        },
        render: (_args, value: any) => [
          {
            type: 'text',
            text: `<mesh_dispatch peer="${value.fromNodeId}" task="${value.taskId}" success="${value.success}">\n${JSON.stringify(value.result || value.error, null, 2)}\n</mesh_dispatch>`
          }
        ]
      },
      async execute(args: any): Promise<any> {
        return service.dispatchTask(args.peer_id, args.tool_name, args.arguments || {});
      }
    })
  );
}
