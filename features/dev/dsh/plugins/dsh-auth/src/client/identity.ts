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

/**
 * Fetch the tenant identity from the server. The session cookie is HttpOnly, so
 * JS cannot read it via document.cookie; this endpoint returns the identity that
 * the server authenticated. Falls back to parseTenantIdentity() on any error so
 * the UI still renders (e.g. before the first fetch resolves).
 */
export async function fetchTenantIdentity(): Promise<TenantIdentity> {
  try {
    if (typeof fetch !== 'undefined') {
      const res = await fetch('/auth/identity', { headers: { accept: 'application/json' }, credentials: 'same-origin' });
      if (res.ok) {
        const body = await res.json();
        if (body && typeof body.username === 'string') {
          return {
            username: body.username,
            clearance: body.clearance || 'Member',
            provider: body.provider || 'unknown',
            groups: Array.isArray(body.groups) ? body.groups : [],
          };
        }
      }
    }
  } catch {
    // Fall through to cookie/local parse
  }
  return parseTenantIdentity();
}
