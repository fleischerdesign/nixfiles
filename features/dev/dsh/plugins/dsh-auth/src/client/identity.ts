export interface TenantIdentity {
  username: string;
  clearance: 'Admin' | 'Restricted' | string;
  provider: string;
  groups: string[];
}

export function parseTenantIdentity(): TenantIdentity {
  const fallback: TenantIdentity = {
    username: 'local',
    clearance: 'Admin',
    provider: 'loopback',
    groups: ['wheel'],
  };

  if (typeof document === 'undefined') {
    return fallback;
  }

  try {
    const cookies = document.cookie.split(';');
    for (const c of cookies) {
      const trimmed = c.trim();
      if (trimmed.startsWith('dsh-auth-')) {
        const parts = trimmed.split('=')[1]?.split('.');
        if (parts && parts.length === 3 && parts[0] === 'v1') {
          const payload = JSON.parse(atob(parts[1].replace(/-/g, '+').replace(/_/g, '/')));
          if (payload?.identity) {
            return {
              username: payload.identity.username || fallback.username,
              clearance: payload.identity.clearance || fallback.clearance,
              provider: payload.identity.provider || fallback.provider,
              groups: Array.isArray(payload.identity.groups) && payload.identity.groups.length > 0
                ? payload.identity.groups
                : fallback.groups,
            };
          }
        }
      }
    }
  } catch {
    // Return fallback on parse errors
  }

  return fallback;
}
