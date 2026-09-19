{
  config,
  lib,
  flake ? null,
  ...
}:

let
  cfg = config.my.features.services.monitoring.prometheus;
  hosts = config.my.topology.hosts or { };
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

  # Flatten all endpoint contracts per host across cluster
  endpointsByHost =
    let
      configs = if flake != null then flake.nixosConfigurations or { } else { ${ownHost} = config; };
    in
    lib.mapAttrs (
      _hostName: hostCfg:
      let
        provides = hostCfg.config.my.contracts.provides or { };
      in
      lib.concatLists (
        lib.mapAttrsToList (
          svcName: contract:
          lib.mapAttrsToList (epName: ep: {
            name = if epName == "default" || epName == "web" then svcName else "${svcName}-${epName}";
            inherit ep;
          }) contract.endpoints
        ) provides
      )
    ) configs;

  hostsWithBlackbox = lib.filterAttrs (
    _: hostCfg: hostCfg.config.my.features.services.monitoring.blackbox-exporter.enable or false
  ) (if flake != null then (flake.nixosConfigurations or { }) else { ${ownHost} = config; });

  blackboxAddrForHost =
    hostName:
    if hostName == ownHost then "127.0.0.1:9115" else "${hosts.${hostName}.wireguardIpv4}:9115";

  # Collect all direct Prometheus scrape targets across hosts
  allScrapeServices = lib.concatLists (
    lib.mapAttrsToList (
      hostName: epList:
      lib.map (item: {
        svcName = item.name;
        inherit hostName;
        svc = item.ep;
      }) (lib.filter (item: item.ep.monitoring.scrape.enable) epList)
    ) endpointsByHost
  );

  # Group by service name to prevent the job-per-host anti-pattern
  groupedScrapeServices = lib.groupBy (x: x.svcName) allScrapeServices;

  # Collect all local HTTP Blackbox probes and group them under a single job using exporter_address relabeling
  allHttpLocalProbes = lib.concatLists (
    lib.mapAttrsToList (
      hostName: epList:
      if hostsWithBlackbox ? ${hostName} then
        lib.map (item: {
          target = item.ep.localUrl + item.ep.monitoring.http.path;
          labels = {
            service = item.name;
            host = hostName;
            probe_type = "http_local";
            group = item.ep.monitoring.http.group;
            exporter_address = blackboxAddrForHost hostName;
          };
        }) (lib.filter (item: item.ep.monitoring.http.enable) epList)
      else
        [ ]
    ) endpointsByHost
  );

  # Collect all local TCP Blackbox probes and group them under a single job using exporter_address relabeling
  allTcpLocalProbes = lib.concatLists (
    lib.mapAttrsToList (
      hostName: epList:
      if hostsWithBlackbox ? ${hostName} then
        lib.map (item: {
          target = "127.0.0.1:${toString item.ep.port}";
          labels = {
            service = item.name;
            host = hostName;
            probe_type = "tcp_local";
            group = item.ep.monitoring.tcp.group;
            exporter_address = blackboxAddrForHost hostName;
          };
        }) (lib.filter (item: item.ep.monitoring.tcp.enable) epList)
      else
        [ ]
    ) endpointsByHost
  );

  # Public HTTP probes
  httpPublicServices = lib.concatLists (
    lib.mapAttrsToList (
      hostName: epList:
      lib.map
        (item: {
          inherit (item) name;
          inherit hostName;
          ep = item.ep;
        })
        (
          lib.filter (
            item:
            (item.ep.scope == "public" || item.ep.scope == "internal")
            && item.ep.monitoring.http.enable
            && item.ep.publicUrl != null
          ) epList
        )
    ) endpointsByHost
  );

  otherServerHosts = lib.filterAttrs (
    n: h: n != ownHost && (h.hostType or "client") == "server" && h.wireguardIpv4 != null
  ) hosts;

  embeddedHosts = lib.filterAttrs (_: h: (h.hostType or "") == "embedded" && h.ipv4 != null) hosts;
  iotDevices = lib.filterAttrs (_: d: d.ipv4 != null) (config.my.topology.devices or { });
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
              (
                if t.hostName == ownHost then
                  "127.0.0.1:${toString t.svc.monitoring.scrape.port}"
                else
                  "${hosts.${t.hostName}.wireguardIpv4}:${toString t.svc.monitoring.scrape.port}"
              )
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
          lib.optionals (httpPublicServices != [ ]) [
            {
              job_name = "blackbox-http-public";
              scrape_interval = "1m";
              metrics_path = "/probe";
              params.module = [ "http_2xx" ];
              static_configs = map (item: {
                targets = [ "${item.ep.publicUrl}${item.ep.monitoring.http.path}" ];
                labels = {
                  service = item.name;
                  host = item.hostName;
                  probe_type = "http_public";
                  group = item.ep.monitoring.http.group;
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

          # Ping probe for servers over Tailscale mesh
          lib.optionals (otherServerHosts != { }) [
            {
              job_name = "blackbox-ping-servers";
              scrape_interval = "1m";
              metrics_path = "/probe";
              params.module = [ "icmp" ];
              static_configs = lib.mapAttrsToList (name: host: {
                targets = [ host.wireguardIpv4 ];
                labels = {
                  target_host = name;
                  probe_type = "icmp_mesh";
                  group = "Mesh-Hosts";
                };
              }) otherServerHosts;
              relabel_configs = blackboxRelabel "127.0.0.1:9115";
            }
          ]

        ++

          # Probing of embedded devices (Gateway, Access Point) via ICMP
          lib.optionals (embeddedHosts != { }) [
            {
              job_name = "blackbox-icmp-embedded";
              scrape_interval = "1m";
              metrics_path = "/probe";
              params.module = [ "icmp" ];
              static_configs = lib.mapAttrsToList (name: host: {
                targets = [ host.ipv4 ];
                labels = {
                  target_host = name;
                  probe_type = "icmp_embedded";
                  group = "Infrastructure";
                };
              }) embeddedHosts;
              relabel_configs = blackboxRelabel "127.0.0.1:9115";
            }
          ]

        ++

          # Probing of IoT devices (Relays, Tasmota/ESPHome) via ICMP
          lib.optionals (iotDevices != { }) [
            {
              job_name = "blackbox-icmp-iot";
              scrape_interval = "1m";
              metrics_path = "/probe";
              params.module = [ "icmp" ];
              static_configs = lib.mapAttrsToList (name: dev: {
                targets = [ dev.ipv4 ];
                labels = {
                  device = name;
                  probe_type = "icmp_iot";
                  group = dev.group or "IoT";
                };
              }) iotDevices;
              relabel_configs = blackboxRelabel "127.0.0.1:9115";
            }
          ];
    };

    my.contracts.provides.prometheus = {
      endpoints.web = {
        port = 9090;
        protocol = "tcp";
        scope = "internal";
        auth = "none";
        monitoring = {
          tcp.enable = true;
          tcp.group = "Infrastructure";
          scrape.enable = true;
          scrape.port = 9090;
        };
      };
    };
  };
}
