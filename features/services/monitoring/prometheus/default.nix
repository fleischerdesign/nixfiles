{
  config,
  lib,
  flake ? null,
  ...
}:

let
  cfg = config.my.features.services.monitoring.prometheus;
  hosts = config.my.features.system.networking.topology.hosts or { };
  ownHost = config.networking.hostName;

  blackboxRelabel = blackboxAddr: [
    {
      source_labels = [ "__address__" ];
      target_label = "__param_target";
    }
    {
      source_labels = [ "__param_target" ];
      target_label = "instance";
    }
    {
      target_label = "__address__";
      replacement = blackboxAddr;
    }
  ];

  registriesByHost =
    if flake != null then
      lib.mapAttrs (_: hostCfg: hostCfg.config.my.endpoints or { }) (flake.nixosConfigurations or { })
    else
      { ${ownHost} = config.my.endpoints or { }; };

  hostsWithBlackbox = lib.filterAttrs (
    _: hostCfg: hostCfg.config.my.features.services.monitoring.blackbox-exporter.enable or false
  ) (flake.nixosConfigurations or { });

  allServices = lib.foldl' (acc: registry: acc // registry) { } (
    builtins.attrValues registriesByHost
  );

  httpPublicServices = lib.filterAttrs (
    _: svc: svc.proxy.enable && svc.monitoring.http.enable && svc.publicUrl != null
  ) allServices;

  otherServerHosts = lib.filterAttrs (n: h: n != ownHost && h.hostType or "client" == "server") hosts;

  blackboxAddrForHost =
    hostName: if hostName == ownHost then "127.0.0.1:9115" else "${hosts.${hostName}.tailscaleIp}:9115";

  # Collect all direct Prometheus scrape targets across hosts
  allScrapeServices = lib.concatLists (
    lib.mapAttrsToList (hostName: registry:
      lib.mapAttrsToList (svcName: svc: {
        inherit svcName hostName svc;
      }) (lib.filterAttrs (_: svc: svc.monitoring.scrape.enable or false) registry)
    ) registriesByHost
  );

  # Group by service name to prevent the job-per-host anti-pattern
  groupedScrapeServices = lib.groupBy (x: x.svcName) allScrapeServices;

  # Collect all local HTTP Blackbox probes and group them under a single job using exporter_address relabeling
  allHttpLocalProbes = lib.concatLists (
    lib.mapAttrsToList (hostName: registry:
      if hostsWithBlackbox ? ${hostName} then
        lib.mapAttrsToList (svcName: svc: {
          target = svc.localUrl + svc.monitoring.http.path;
          labels = {
            service = svcName;
            host = hostName;
            probe_type = "http_local";
            group = svc.monitoring.http.group;
            exporter_address = blackboxAddrForHost hostName;
          };
        }) (lib.filterAttrs (_: svc: svc.monitoring.http.enable) registry)
      else
        [ ]
    ) registriesByHost
  );

  # Collect all local TCP Blackbox probes and group them under a single job using exporter_address relabeling
  allTcpLocalProbes = lib.concatLists (
    lib.mapAttrsToList (hostName: registry:
      if hostsWithBlackbox ? ${hostName} then
        lib.mapAttrsToList (svcName: svc: {
          target = "127.0.0.1:${toString svc.port}";
          labels = {
            service = svcName;
            host = hostName;
            probe_type = "tcp_local";
            group = svc.monitoring.tcp.group;
            exporter_address = blackboxAddrForHost hostName;
          };
        }) (lib.filterAttrs (_: svc: svc.monitoring.tcp.enable) registry)
      else
        [ ]
    ) registriesByHost
  );
in
{
  options.my.features.services.monitoring.prometheus = {
    enable = lib.mkEnableOption "Prometheus Server";
  };

  config = lib.mkIf cfg.enable {
    services.prometheus = {
      enable = true;
      port = 9090;

      scrapeConfigs =
        # Unified Prometheus scrape targets grouped by job name
        (lib.mapAttrsToList (svcName: targetsList: {
          job_name = svcName;
          metrics_path = (lib.head targetsList).svc.monitoring.scrape.path;
          static_configs = map (t: {
            targets = [
              (if t.hostName == ownHost then
                "127.0.0.1:${toString t.svc.monitoring.scrape.port}"
              else
                "${hosts.${t.hostName}.tailscaleIp}:${toString t.svc.monitoring.scrape.port}")
            ];
            labels = {
              host = t.hostName;
            };
          }) targetsList;
          relabel_configs = [
            {
              source_labels = [ "host" ];
              target_label = "instance";
            }
          ];
        }) groupedScrapeServices)

        ++

          # Unified local HTTP probes under a single blackbox-http-local job
          lib.optionals (allHttpLocalProbes != [ ]) [
            {
              job_name = "blackbox-http-local";
              scrape_interval = "1m";
              metrics_path = "/probe";
              params.module = [ "http_2xx" ];
              static_configs = map (p: {
                targets = [ p.target ];
                labels = p.labels;
              }) allHttpLocalProbes;
              relabel_configs = [
                {
                  source_labels = [ "__address__" ];
                  target_label = "__param_target";
                }
                {
                  source_labels = [ "service" ];
                  target_label = "instance";
                }
                {
                  source_labels = [ "exporter_address" ];
                  target_label = "__address__";
                }
              ];
            }
          ]

        ++

          # Public HTTP probes using computed registry URLs
          lib.optionals (httpPublicServices != { }) [
            {
              job_name = "blackbox-http-public";
              scrape_interval = "1m";
              metrics_path = "/probe";
              params.module = [ "http_2xx" ];
              static_configs = lib.mapAttrsToList (name: svc: {
                targets = [ "${svc.publicUrl}${svc.monitoring.http.path}" ];
                labels = {
                  service = name;
                  inherit (svc) host;
                  probe_type = "http_public";
                  group = svc.monitoring.http.group;
                };
              }) httpPublicServices;
              relabel_configs = blackboxRelabel "127.0.0.1:9115";
            }
          ]

        ++

          # Unified local TCP probes under a single blackbox-tcp-local job
          lib.optionals (allTcpLocalProbes != [ ]) [
            {
              job_name = "blackbox-tcp-local";
              scrape_interval = "1m";
              metrics_path = "/probe";
              params.module = [ "tcp_connect" ];
              static_configs = map (p: {
                targets = [ p.target ];
                labels = p.labels;
              }) allTcpLocalProbes;
              relabel_configs = [
                {
                  source_labels = [ "__address__" ];
                  target_label = "__param_target";
                }
                {
                  source_labels = [ "service" ];
                  target_label = "instance";
                }
                {
                  source_labels = [ "exporter_address" ];
                  target_label = "__address__";
                }
              ];
            }
          ]

        ++

          # Blackbox: Tailscale host connectivity
          lib.optionals (otherServerHosts != { }) [
            {
              job_name = "blackbox-tailscale";
              scrape_interval = "1m";
              metrics_path = "/probe";
              params.module = [ "tcp_connect" ];
              static_configs = lib.mapAttrsToList (name: host: {
                targets = [ "${host.tailscaleIp}:22" ];
                labels = {
                  service = "${name}-ssh";
                  host = name;
                  probe_type = "tailscale";
                  group = "Tailscale";
                };
              }) otherServerHosts;
              relabel_configs = blackboxRelabel "127.0.0.1:9115";
            }
          ];
    };

    my.endpoints.prometheus = {
      host = config.networking.hostName;
      port = 9090;
      monitoring = {
        tcp.enable = true;
        tcp.group = "Infrastructure";
        scrape.enable = true;
        scrape.port = 9090;
      };
    };
  };
}
