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

export interface PeerPresence {
  tenants: string[]; // usernames with an authenticated presence on that node
  groups: string[];  // e.g. ['group:dev', 'group:family']
  updatedAt: number;
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
  /** Presence advertised by this peer (tenant/group-level), from its heartbeat. */
  presence?: PeerPresence;
}

export interface HeartbeatPayload {
  nodeId: string;
  timestamp: number;
  maxTx: number;
  /** Advertisement of locally-hosted tenants/groups (agnostic presence). */
  presence?: { tenants: string[]; groups: string[] };
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

export interface RemoteSessionInfo {
  sessionId: string;
  workspaceUrn: string;
  workspaceLabel?: string;
  workspaceType?: 'git' | 'relhome' | 'raw';
  nodeId: string;
  lastTurnSeq: number;
  updatedAt: number;
  leaseEpoch: number;
  leaseHolder: string;
  isLeaseActive: boolean;
  gitFingerprint?: {
    commit?: string;
    branch?: string;
    isDirty?: boolean;
    diffHash?: string;
  };
  summary?: string;
}

export interface LeaseRecord {
  sessionId: string;
  holderNodeId: string;
  leaseEpoch: number;
  expiresAt: number;
  grantedAt: number;
}

export interface LeaseHandoffRequest {
  sessionId: string;
  requestingNodeId: string;
  currentEpoch: number;
  force?: boolean;
}

export interface LeaseHandoffResponse {
  sessionId: string;
  success: boolean;
  grantedEpoch: number;
  holderNodeId: string;
  lastSeq: number;
  error?: string;
}

export interface LiveStreamChunk {
  sessionId: string;
  fromNodeId: string;
  type: 'token_chunk' | 'tool_in_progress' | 'user_draft' | 'turn_completed';
  payload: any;
  timestamp: number;
}

