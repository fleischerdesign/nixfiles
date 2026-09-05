/**
 * @module @dsh/mesh/types
 * Formal types for distributed peer-to-peer mesh topology, gossip, and CvRDT synchronization.
 */

export interface PeerEndpoint {
  id: string;
  endpoint: string; // "host:port" or URL
  tags?: string[];
}

export interface MeshPluginConfig {
  nodeId: string;
  listenPort?: number;
  listenHost?: string;
  heartbeatIntervalMs?: number;
  leaseTtlMs?: number;
  peers?: PeerEndpoint[];
}

export interface PeerStatus {
  id: string;
  endpoint: string;
  lastHeartbeatMs: number;
  rttMs: number;
  healthy: boolean;
  maxTxSeen: number;
}

export interface HeartbeatPayload {
  nodeId: string;
  timestamp: number;
  maxTx: number;
}

export interface SyncDeltaRequest {
  fromNodeId: string;
  sinceTx: number;
}

export interface SyncDeltaResponse {
  fromNodeId: string;
  facts: any[];
  maxTx: number;
}
