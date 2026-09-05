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
