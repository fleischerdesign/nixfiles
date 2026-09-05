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
}
