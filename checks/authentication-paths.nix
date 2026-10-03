{
  lib,
  pkgs,
  self,
  ...
}:
let
  systems = self.nixosConfigurations;
  server = systems.cld-edge-01.config;
  consumers = server.my.features.services.authentik.server.httpConsumerHosts;
  endpoint = server.my.contracts.provides.authentik.endpoints.web;
  home = systems.hom-srv-01.config;
  seerr = home.my.contracts.provides.jellyseerr;
  publication = seerr.publications.web;
  integration = seerr.identity.oidc.web;
  setup = home.systemd.services.seerr-oidc-configure.serviceConfig.ExecStart;
  # ExecStart references the generated non-secret JSON immediately before the credential argument.
  desired = builtins.elemAt (lib.splitString " " setup) 4;
  sources = import ../contracts/topology/lib/access-sources.nix { inherit lib; };
  rules = lib.filter (line: lib.hasInfix "tcp dport ${toString endpoint.port} " line) (
    lib.splitString "\n" server.networking.firewall.extraInputRules
  );
  metadata = pkgs.writeText "authentication-paths.json" (
    builtins.toJSON (
      lib.mapAttrs (name: system: {
        inherit name;
        required = system.config.my.features.services.caddy.forwardAuthRequired;
        address = system.config.my.features.services.caddy.authentikOutpostAddress;
      }) (lib.filterAttrs (_: system: system.config.my.features.services.caddy.enable) systems)
    )
  );
in
assert
  consumers == [
    "cld-ops-01"
    "hom-srv-01"
  ];
assert endpoint.directAccess.enable && endpoint.directAccess.interface == "wireguard";
assert endpoint.directAccess.from == [ ] && endpoint.directAccess.fromHosts == consumers;
assert lib.all (source: lib.any (rule: lib.hasInfix source rule) rules) (
  sources.sourcesOfHosts server.my.topology (consumers ++ [ server.my.topology.ingressHost ])
);
assert !lib.any (rule: lib.hasInfix server.my.topology.hosts.hom-wrk-01.wireguardIpv4 rule) rules;
assert publication.auth == "oidc";
assert
  integration.redirectUris == [ "${publication.publicUrl}/login?provider=authentik&callback=true" ];
assert
  !lib.hasInfix "forward_auth"
    server.services.caddy.virtualHosts.${publication.canonicalDomain}.extraConfig;
assert integration.secretPath == home.my.features.services.jellyseerr.oidc.secretPath;
pkgs.runCommand "authentication-paths-check"
  {
    nativeBuildInputs = [
      pkgs.caddy
      pkgs.python3
    ];
  }
  ''
    set -euo pipefail
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (
        name: system:
        lib.optionalString system.config.my.features.services.caddy.enable ''
          caddy adapt --config ${system.config.services.caddy.configFile} --adapter caddyfile > ${name}.json
        ''
      ) systems
    )}
    python3 ${./authentication-paths.py} ${metadata}
    python3 ${./seerr-oidc.py} ${../features/services/jellyseerr/configure-oidc.py} ${desired} \
      ${lib.escapeShellArg "${server.my.contracts.provides.authentik.publications.web.publicUrl}/application/o/jellyseerr/"}
    touch $out
  ''
