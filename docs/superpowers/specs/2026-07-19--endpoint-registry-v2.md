# Endpoint Registry v2 — Design Spec

## Goal
`my.endpoints` evolves from a Caddy-exclusive registry into a universal
service topology registry. Firewall rules, monitoring probes, and reverse
proxy configs all derive from a single source of truth.

## Schema

### Current (v1)
```nix
my.endpoints.<name> = {
  host = "hostname";
  port = 8123;
  subdomain = "foo";       # Caddy vHost
  fullDomain = "foo.bar";  # override subdomain+baseDomain
  auth = true;             # Authentik forward-auth
  caddy.enable = true;     # default: Caddy manages reverse proxy
  monitoring.http.enable = true;
  monitoring.tcp.enable = false;
  monitoring.scrape.enable = false;
};
```

### New (v2)
```nix
my.endpoints.<name> = {
  host = "hostname";
  port = 8123;
  fullDomain = "foo.bar";  # unchanged

  proxy = {                # NEW: groups Caddy concerns
    enable = false;        # default: OFF — must opt in explicitly
    subdomain = "foo";
    websocket = false;
    auth = false;
  };

  directAccess = {         # NEW: firewall exposition
    enable = false;        # default: OFF — must opt in explicitly
  };

  monitoring = { ... };    # unchanged
};
```

## Migration Plan

### Affected files
- `features/endpoints/default.nix` — schema definition
- `features/services/caddy/default.nix` — consumer
- `hosts/rollins/configuration.nix` — endpoint config
- `hosts/strummer/configuration.nix` — endpoint config
- `features/services/home-assistant/default.nix` — endpoint + firewall
- `features/services/klipper/default.nix` — endpoint (caddy.enable=false) + firewall
- `features/services/paperless/default.nix` — subdomain reference
- `features/services/mealie/default.nix` — subdomain reference
- `features/services/hermes-agent/default.nix` — subdomain reference
- `features/services/sabnzbd/default.nix` — subdomain reference
- `features/services/ntfy/default.nix` — subdomain reference
- `features/system/common/firewall.nix` — NEW

### Safety invariants
- No service loses its Caddy vHost during migration
- No port silently opens or closes in firewall
- Every endpoint field read uses `or` fallback for backward compat during transition
