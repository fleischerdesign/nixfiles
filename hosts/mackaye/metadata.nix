{
  role = "server";
  features = {
    # Basic Infrastructure
    system.networking.tailscale.enable = true;
    services.caddy.enable = true;
    services.monitoring.node-exporter.enable = true;
    
    services.postgresql.enable = true;
    services.redis.enable = true;
    services.authentik.enable = true;
    services.plausible.enable = true;
    
    # Dev Tools
    dev.nixvim.enable = true;
  };
}
