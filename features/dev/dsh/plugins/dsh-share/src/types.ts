/**
 * Types and schema for Capability-Based Session Sharing.
 */

export type ShareScope = 'public' | `group:${string}` | `user:${string}`;
export type ShareAccessMode = 'snapshot' | 'live';
export type SharePermission = 'view' | 'fork' | 'collaborate';

export interface ShareAclEntry {
  grantee: string; // 'group:dev' | 'user:alice'
  permission: SharePermission;
  grantedAt: number;
}

export interface ShareOptions {
  sessionId: string;
  scope: ShareScope;
  accessMode: ShareAccessMode;
  permission: SharePermission;
  stripSecrets?: boolean;
  ttlSeconds?: number; // 0 = permanent
  allowedGroups?: string[];
  allowedUsers?: string[];
}

export interface SharedSessionRecord {
  shareId: string;
  token: string;
  sessionId: string;
  owner: string;
  title: string;
  scope: ShareScope;
  accessMode: ShareAccessMode;
  permission: SharePermission;
  stripSecrets: boolean;
  createdAt: number;
  expiresAt: number; // 0 = never
  revoked: boolean;
  acl: ShareAclEntry[];
  snapshotData?: any; // Serialized redactive message array for snapshots
}

export interface CreateShareResponse {
  shareId: string;
  token: string;
  shareUrl: string;
  scope: ShareScope;
  permission: SharePermission;
  expiresAt: number;
}

export interface SessionShareListResponse {
  shares: Array<{
    shareId: string;
    token: string;
    shareUrl: string;
    scope: ShareScope;
    permission: SharePermission;
    createdAt: number;
    expiresAt: number;
    revoked: boolean;
  }>;
  acl: ShareAclEntry[];
}
