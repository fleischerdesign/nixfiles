{
  config,
  lib,
  flake ? null,
  ...
}:

let
  cfg = config.my.features.services.gatus;

  # Services from this host's registry
  localServices = config.my.registry or { };

  # Services from other hosts (aggregated via flake for cross-host monitoring)
  remoteServices =
    if flake != null then
      lib.foldl' (
        acc: hostCfg:
        let
          svcs = hostCfg.config.my.registry or { };
          remote = lib.filterAttrs (_: svc: svc.host != config.networking.hostName) svcs;
        in
        acc // remote
      ) { } (builtins.attrValues flake.nixosConfigurations)
    else
      { };

  allServices = localServices // remoteServices;

  # Resolve the public domain for a service (for external probes)
  resolveDomain =
    svc:
    if svc.fullDomain != null then
      svc.fullDomain
    else if svc.subdomain != null then
      let
        hostDomain = config.my.features.system.networking.topology.hosts.${svc.host}.domain or svc.host;
      in
      "${svc.subdomain}.${hostDomain}"
    else
      null;

  # HTTP services (local): internal probe
  httpInternal = lib.filterAttrs (
    _: svc: svc.monitoring.http.enable && resolveDomain svc != null
  ) localServices;

  # HTTP services (all hosts): external probe
  httpExternal = lib.filterAttrs (
    _: svc: svc.monitoring.http.enable && resolveDomain svc != null
  ) allServices;

  # TCP services (local only): infrastructure probe
  tcpLocal = lib.filterAttrs (_: svc: svc.monitoring.tcp.enable) localServices;
in
{
  options.my.features.services.gatus = {
    enable = lib.mkEnableOption "Gatus status page";

    internalProbes = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "HTTP probes via 127.0.0.1 for local services";
    };

    externalProbes = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "HTTP probes via public domain for all services";
    };

    tcpProbes = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "TCP probes for infrastructure services";
    };

    tailscaleProbes = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "TCP probes via Tailscale for other server hosts from topology";
    };

    extraEndpoints = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [ ];
      description = "Additional endpoints to append to the auto-generated list";
    };
  };

  config = lib.mkIf cfg.enable {
    services.gatus = {
      enable = true;

      settings = {
        web = {
          port = 8088;
          address = "127.0.0.1";
        };

        storage = {
          type = "sqlite";
          path = "/var/lib/gatus/data.db";
        };

        metrics = true;

        endpoints =
          # Internal HTTP probes (local services only)
          (lib.optionals cfg.internalProbes (
            lib.mapAttrsToList (name: svc: {
              name = "${name} (internal)";
              group = svc.monitoring.http.group;
              url = "http://127.0.0.1:${toString svc.port}${svc.monitoring.http.path}";
              conditions = svc.monitoring.http.conditions;
              interval = svc.monitoring.http.interval;
            }) httpInternal
          ))
          ++
            # External HTTP probes (all services across all hosts)
            (lib.optionals cfg.externalProbes (
              lib.mapAttrsToList (name: svc: {
                name = "${name} (external)";
                group = svc.monitoring.http.group;
                url = "https://${resolveDomain svc}${svc.monitoring.http.path}";
                conditions = svc.monitoring.http.conditions;
                interval = svc.monitoring.http.interval;
              }) httpExternal
            ))
          ++
            # TCP probes (local infrastructure services)
            (lib.optionals cfg.tcpProbes (
              lib.mapAttrsToList (name: svc: {
                inherit name;
                group = svc.monitoring.tcp.group;
                url = "tcp://127.0.0.1:${toString svc.port}";
                conditions = svc.monitoring.tcp.conditions;
                interval = svc.monitoring.tcp.interval;
              }) tcpLocal
            ))
          ++
            # Tailscale probes for other server hosts
            (lib.optionals cfg.tailscaleProbes (
              let
                allHosts = config.my.features.system.networking.topology.hosts or { };
                otherHosts = lib.filterAttrs (
                  n: h: n != config.networking.hostName && h.hostType or "client" == "server"
                ) allHosts;
              in
              lib.mapAttrsToList (name: host: {
                inherit name;
                group = "Tailscale";
                url = "tcp://${host.tailscaleIp}:22";
                conditions = [ "[CONNECTED] == true" ];
                interval = "5m";
              }) otherHosts
            ))
          ++ cfg.extraEndpoints;
      };
    };

    # Expose via Caddy
    my.registry.gatus = {
      host = config.networking.hostName;
      port = 8088;
      subdomain = "status";
    };
  };
}
