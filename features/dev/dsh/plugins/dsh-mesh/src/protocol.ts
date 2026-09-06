import * as http from 'node:http';
import type { HeartbeatPayload, SyncDeltaRequest, SyncDeltaResponse } from './types.js';

export class MeshTransportClient {
  private timeoutMs: number;

  constructor(timeoutMs = 5000) {
    this.timeoutMs = timeoutMs;
  }

  async sendHeartbeat(endpoint: string, payload: HeartbeatPayload): Promise<{ rttMs: number; response: HeartbeatPayload }> {
    const start = Date.now();
    const url = endpoint.startsWith('http') ? endpoint : `http://${endpoint}`;

    const res = await this.postJson<HeartbeatPayload, HeartbeatPayload>(`${url}/mesh/heartbeat`, payload);
    return {
      rttMs: Date.now() - start,
      response: res
    };
  }

  async fetchDelta(endpoint: string, req: SyncDeltaRequest): Promise<SyncDeltaResponse> {
    const url = endpoint.startsWith('http') ? endpoint : `http://${endpoint}`;
    return this.postJson<SyncDeltaRequest, SyncDeltaResponse>(`${url}/mesh/sync`, req);
  }

  async listRemoteSessions(endpoint: string): Promise<any[]> {
    const url = endpoint.startsWith('http') ? endpoint : `http://${endpoint}`;
    return this.getJson<any[]>(`${url}/mesh/sessions`);
  }

  async requestLeaseHandoff(endpoint: string, req: any): Promise<any> {
    const url = endpoint.startsWith('http') ? endpoint : `http://${endpoint}`;
    return this.postJson(`${url}/mesh/lease/handoff`, req);
  }

  async broadcastLiveChunk(endpoint: string, chunk: any): Promise<void> {
    const url = endpoint.startsWith('http') ? endpoint : `http://${endpoint}`;
    await this.postJson(`${url}/mesh/stream/chunk`, chunk).catch(() => {});
  }

  async executeRemoteTask(endpoint: string, req: any, hmacSecret?: string): Promise<any> {
    const url = endpoint.startsWith('http') ? endpoint : `http://${endpoint}`;
    return this.postJson(`${url}/mesh/task`, req);
  }

  private getJson<TRes>(urlStr: string): Promise<TRes> {
    return new Promise((resolve, reject) => {
      const url = new URL(urlStr);
      const req = http.request(
        {
          hostname: url.hostname,
          port: url.port || 80,
          path: `${url.pathname}${url.search}`,
          method: 'GET',
          headers: {
            'Accept': 'application/json'
          },
          timeout: this.timeoutMs
        },
        (res) => {
          let resData = '';
          res.on('data', (d) => { resData += d; });
          res.on('end', () => {
            if (res.statusCode && res.statusCode >= 200 && res.statusCode < 300) {
              try {
                resolve(JSON.parse(resData));
              } catch (e) {
                reject(new Error(`Failed to parse mesh JSON response: ${e}`));
              }
            } else {
              reject(new Error(`Mesh GET failed with status: ${res.statusCode}`));
            }
          });
        }
      );
      req.on('error', reject);
      req.on('timeout', () => {
        req.destroy();
        reject(new Error('Mesh transport timeout'));
      });
      req.end();
    });
  }

  private postJson<TReq, TRes>(urlStr: string, body: TReq): Promise<TRes> {
    return new Promise((resolve, reject) => {
      const url = new URL(urlStr);
      const data = JSON.stringify(body);

      const req = http.request(
        {
          hostname: url.hostname,
          port: url.port || 80,
          path: url.pathname,
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Content-Length': Buffer.byteLength(data)
          },
          timeout: this.timeoutMs
        },
        (res) => {
          let resData = '';
          res.on('data', (d) => { resData += d; });
          res.on('end', () => {
            if (res.statusCode && res.statusCode >= 200 && res.statusCode < 300) {
              try {
                resolve(JSON.parse(resData));
              } catch (e) {
                reject(new Error(`Failed to parse mesh JSON response: ${e}`));
              }
            } else {
              reject(new Error(`Mesh request failed with status: ${res.statusCode}`));
            }
          });
        }
      );

      req.on('error', reject);
      req.on('timeout', () => {
        req.destroy();
        reject(new Error('Mesh transport timeout'));
      });

      req.write(data);
      req.end();
    });
  }
}
