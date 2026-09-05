/**
 * Types and interfaces for the @dsh/auth authentication and identity gateway.
 */

export type ClearanceLevel = 'Restricted' | 'Member' | 'Admin';

export interface UserIdentity {
  id: string;
  username: string;
  email?: string;
  displayName?: string;
  groups: string[];
  clearance: ClearanceLevel;
  provider: 'forward-proxy' | 'oidc' | 'ldap' | 'loopback' | 'peer-mesh';
}

export interface ForwardProxyConfig {
  enabled: boolean;
  trustedProxies?: string[]; // e.g. ["127.0.0.1", "::1"]
  headerUser?: string;       // Default: "x-authentik-username"
  headerEmail?: string;      // Default: "x-authentik-email"
  headerGroups?: string;     // Default: "x-authentik-groups"
  headerJwt?: string;        // Default: "x-authentik-jwt"
  adminGroups?: string[];    // Groups mapped to Admin clearance, e.g. ["authentik Admins", "wheel"]
  memberGroups?: string[];   // Groups mapped to Member clearance
}

export interface OidcConfig {
  enabled: boolean;
  issuer: string;            // e.g. "https://auth.ancoris.ovh/application/o/dsh/"
  clientId: string;
  clientSecret?: string;
  scopes?: string[];
  adminClaim?: string;       // e.g. "groups"
  adminValues?: string[];    // e.g. ["admin"]
}

export interface LdapConfig {
  enabled: boolean;
  url: string;               // e.g. "ldaps://ldap.ancoris.ovh:636"
  baseDn: string;
  bindDn?: string;
  bindPassword?: string;
  userFilter?: string;       // e.g. "(uid={username})"
  groupFilter?: string;      // e.g. "(memberUid={username})"
  adminGroups?: string[];
}

export interface LoopbackConfig {
  enabled: boolean;
  defaultUser?: string;      // Default local user (e.g. "philipp")
  defaultClearance?: ClearanceLevel; // Default: "Admin"
}

export interface PeerMeshAuthConfig {
  enabled: boolean;
  clusterSecret?: string;    // Shared secret for HMAC-SHA256 signature verification
  allowedTimeDriftMs?: number; // Default: 10000 (10s)
}

export interface TenantQuotaConfig {
  maxBudgetEur?: number;      // Monthly cap C_max in EUR (e.g. 15.0 for Member, 5.0 for Restricted)
  refillRatePerSec?: number;  // Refill rate rho in EUR/sec
}

export interface AuthPluginConfig {
  mode?: 'forward-proxy' | 'oidc' | 'ldap' | 'loopback-only' | 'auto';
  sessionCookieName?: string;
  sessionTtlDays?: number;
  quotas?: {
    Admin?: TenantQuotaConfig;
    Member?: TenantQuotaConfig;
    Restricted?: TenantQuotaConfig;
  };
  forwardProxy?: ForwardProxyConfig;
  oidc?: OidcConfig;
  ldap?: LdapConfig;
  loopback?: LoopbackConfig;
  peerMesh?: PeerMeshAuthConfig;
}

export interface SessionTokenPayload {
  version: number;
  authority: string;
  issuedAt: number;
  expiresAt: number;
  identity: UserIdentity;
}
