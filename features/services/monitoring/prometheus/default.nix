{
  config,
  lib,
  pkgs,
  flake ? null,
  ...
}:

let
  cfg = config.my.features.services.monitoring.prometheus;
  hosts = config.my.features.system.networking.topology.hosts or { };
  ownHost = config.networking.hostName;
  strummerTailscaleIp = hosts.strummer.tailscaleIp or config.networking.hostName;

  resolveDomain =
    svc:
    if svc.fullDomain != null then
      svc.fullDomain
    else if svc.subdomain != null then
      let
        hostDomain = hosts.${svc.host}.domain or svc.host;
      in
      "${svc.subdomain}.${hostDomain}"
    else
      null;

  blackboxRelabel =
    blackboxAddr: [
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
      lib.mapAttrs (_: hostCfg: hostCfg.config.my.registry or { }) (flake.nixosConfigurations or { })
    else
      { ${ownHost} = config.my.registry or { }; };

  hostsWithBlackbox = lib.filterAttrs (
    _: hostCfg: hostCfg.config.my.features.services.monitoring.blackbox-exporter.enable or false
  ) (flake.nixosConfigurations or { });

  httpLocalByHost = lib.mapAttrs (
    hostName: registry: lib.filterAttrs (_: svc: svc.host == hostName && svc.monitoring.http.enable) registry
  ) registriesByHost;

  tcpLocalByHost = lib.mapAttrs (
    hostName: registry: lib.filterAttrs (_: svc: svc.host == hostName && svc.monitoring.tcp.enable) registry
  ) registriesByHost;

  allServices = lib.foldl' (acc: registry: acc // registry) { } (builtins.attrValues registriesByHost);

  httpPublicServices = lib.filterAttrs (
    _: svc: svc.monitoring.http.enable && resolveDomain svc != null
  ) allServices;

  otherServerHosts = lib.filterAttrs (
    n: h: n != ownHost && h.hostType or "client" == "server"
  ) hosts;

  blackboxAddrForHost =
    hostName:
    if hostName == ownHost then "127.0.0.1:9115" else "${hosts.${hostName}.tailscaleIp}:9115";
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
        [
          {
            job_name = "prometheus";
            static_configs = [ { targets = [ "localhost:9090" ]; } ];
          }
          {
            job_name = "node_mackaye";
            static_configs = [ { targets = [ "localhost:9100" ]; } ];
          }
          {
            job_name = "node_strummer";
            static_configs = [ { targets = [ "${strummerTailscaleIp}:9100" ]; } ];
          }
          {
            job_name = "crowdsec_mackaye";
            static_configs = [ { targets = [ "localhost:6060" ]; } ];
          }
          {
            job_name = "crowdsec_strummer";
            static_configs = [ { targets = [ "${strummerTailscaleIp}:6060" ]; } ];
          }
          {
            job_name = "authentik";
            static_configs = [ { targets = [ "localhost:9300" ]; } ];
          }
          {
            job_name = "blocky_strummer";
            static_configs = [ { targets = [ "${strummerTailscaleIp}:4000" ]; } ];
          }
        ]
        ++

          # Blackbox: HTTP local probes per host
          builtins.concatLists (
            builtins.attrValues (
              lib.mapAttrs (hostName: _: [
                {
                  job_name = "blackbox-http-local-${hostName}";
                  scrape_interval = "1m";
                  metrics_path = "/probe";
                  params.module = [ "http_2xx" ];
                  static_configs = lib.mapAttrsToList (name: svc: {
                    targets = [ "http://127.0.0.1:${toString svc.port}${svc.monitoring.http.path}" ];
                    labels = {
                      service = name;
                      host = svc.host;
                      probe_type = "http_local";
                      group = svc.monitoring.http.group;
                    };
                  }) httpLocalByHost.${hostName};
                  relabel_configs = blackboxRelabel (blackboxAddrForHost hostName);
                }
              ]) hostsWithBlackbox
            )
          )
        ++

          # Blackbox: HTTP public probes (only from Mackaye)
          lib.optionals (httpPublicServices != { }) [
            {
              job_name = "blackbox-http-public";
              scrape_interval = "1m";
              metrics_path = "/probe";
              params.module = [ "http_2xx" ];
              static_configs = lib.mapAttrsToList (name: svc: {
                targets = [ "https://${resolveDomain svc}${svc.monitoring.http.path}" ];
                labels = {
                  service = name;
                  host = svc.host;
                  probe_type = "http_public";
                  group = svc.monitoring.http.group;
                };
              }) httpPublicServices;
              relabel_configs = blackboxRelabel "127.0.0.1:9115";
            }
          ]
        ++

          # Blackbox: TCP local probes per host
          builtins.concatLists (
            builtins.attrValues (
              lib.mapAttrs (hostName: _: [
                {
                  job_name = "blackbox-tcp-local-${hostName}";
                  scrape_interval = "1m";
                  metrics_path = "/probe";
                  params.module = [ "tcp_connect" ];
                  static_configs = lib.mapAttrsToList (name: svc: {
                    targets = [ "127.0.0.1:${toString svc.port}" ];
                    labels = {
                      service = name;
                      host = svc.host;
                      probe_type = "tcp_local";
                      group = svc.monitoring.tcp.group;
                    };
                  }) tcpLocalByHost.${hostName};
                  relabel_configs = blackboxRelabel (blackboxAddrForHost hostName);
                }
              ]) hostsWithBlackbox
            )
          )
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

    my.registry.prometheus = {
      host = config.networking.hostName;
      port = 9090;
      monitoring.tcp.enable = true;
      monitoring.tcp.group = "Infrastructure";
    };
  };
}
