/**
 * @module @dsh/mesh/types
 * Formal types for distributed peer-to-peer mesh topology, gossip, and CvRDT synchronization.
 */

export type PeerScope = 'system' | 'user' | 'group';

export interface PeerEndpoint {
  id: string;
  endpoint: string; // "host:port" or URL
  tags?: string[];
  scope?: PeerScope; // 'system' (from Nix), 'user' (per-user), or 'group' (shared team/family node)
  owner?: string; // Username owning this personal node
  group?: string; // Group name if scope === 'group' (e.g. 'dev', 'family')
  dynamic?: boolean; // true if added dynamically via UI
}

export interface MeshPluginConfig {
  nodeId: string;
  listenPort?: number;
  listenHost?: string;
  heartbeatIntervalMs?: number;
  leaseTtlMs?: number;
  peers?: PeerEndpoint[];
  userPeersFile?: string; // Path to persistent user-created peers (~/.dsh/mesh/peers.json)
}

export interface PeerStatus {
  id: string;
  endpoint: string;
  lastHeartbeatMs: number;
  rttMs: number;
  healthy: boolean;
  maxTxSeen: number;
  scope: PeerScope;
  owner?: string;
  group?: string;
  dynamic: boolean;
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

export interface DelegationCapability {
  taskId: string;
  issuedFor: string; // e.g. "user:philipp"
  authorizedGroup?: string; // e.g. "group:dev"
  allowedTools?: string[];
  expiresAt: number;
  signature?: string;
}

export interface RemoteTaskRequest {
  fromNodeId: string;
  taskId: string;
  toolName: string;
  arguments: Record<string, any>;
  timestamp: number;
  capability?: DelegationCapability;
}

export interface RemoteTaskResponse {
  fromNodeId: string;
  taskId: string;
  success: boolean;
  result?: any;
  error?: string;
  executedAt: number;
}
