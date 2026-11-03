# The Nix device allowlist, the client configuration and the firewall must agree across hosts.
# A mismatch is not visible on either host alone: a client that is enabled without an allowlist entry
# cannot mint, and a client whose mesh source address is missing from the firewall cannot reach the
# listener at all. This check names both.
{
  lib,
  pkgs,
  self,
  ...
}:
let
  systems = self.nixosConfigurations;
  server = systems.cld-ops-01.config;
  serverFeature = server.my.features.dev.openchamber.server;
  clientHosts = lib.attrNames (
    lib.filterAttrs (_: host: host.config.my.features.dev.openchamber.client.enable or false) systems
  );
  endpoint = server.my.contracts.provides.openchamber.endpoints.web;
  firewallRules = lib.splitString "\n" server.networking.firewall.extraInputRules;
  authorizedKeys = server.users.users.openchamber-bootstrap.openssh.authorizedKeys.keys;
  expectedFromHosts = clientHosts ++ [ "mob-ph-01" ];
  serverAddress = server.my.topology.hosts.cld-ops-01.wireguardIpv4;
  expectedUrl = "http://${serverAddress}:${toString endpoint.port}";
  mintConfig = builtins.fromJSON (
    builtins.readFile server.environment.etc."openchamber/mint.json".source
  );
  revokeConfig = builtins.fromJSON (
    builtins.readFile server.environment.etc."openchamber/revoke.json".source
  );
  dport = "tcp dport ${toString endpoint.port}";
  rulesForEndpoint = lib.filter (rule: lib.hasInfix dport rule) firewallRules;
  sshRules = lib.filter (rule: lib.hasInfix "tcp dport 22" rule) firewallRules;
  meshInterface = server.my.features.system.networking.wireguard.interfaceName;
in
assert
  clientHosts == [
    "hom-wrk-01"
    "mob-nb-01"
  ];
assert lib.attrNames serverFeature.devices == clientHosts;
assert serverFeature.meshClientHosts == [ "mob-ph-01" ];
assert lib.all (host: serverFeature.devices.${host}.sshPublicKey != "") clientHosts;
assert lib.all (
  host: systems.${host}.config.my.features.dev.openchamber.client.deviceId == host
) clientHosts;
assert lib.all (
  host:
  let
    remoteHosts = systems.${host}.config.my.features.dev.openchamber.client.remoteHosts;
    central = lib.findFirst (entry: entry.id == "cld-ops-01") null remoteHosts;
  in
  central != null && central.url == expectedUrl && central.sshAddress == serverAddress
) clientHosts;
# A publication would create a name and an ingress hop; the user decided on a mesh-only service.
assert server.my.contracts.provides.openchamber.publications == { };
assert endpoint.directAccess.enable;
assert endpoint.directAccess.interface == "wireguard";
assert server.services.openchamber.host == serverAddress;
assert server.services.openchamber.port == endpoint.port;
assert server.services.openchamber.user == "openchamber";
assert
  server.services.openchamber.uiPasswordFile
  == server.sops.secrets."services/openchamber/ui_password".path;
# The local mint/revoke helpers must dial the address the unit binds; loopback is not bound.
assert mintConfig.serverUrl == expectedUrl;
assert revokeConfig.serverUrl == expectedUrl;
assert builtins.length endpoint.directAccess.fromHosts == builtins.length expectedFromHosts;
assert lib.all (host: lib.elem host endpoint.directAccess.fromHosts) expectedFromHosts;
assert endpoint.directAccess.from == [ ];
assert lib.all (
  host: !(server.sops.secrets ? "services/openchamber/devices/${host}/ssh_key")
) clientHosts;
assert server.sops.secrets ? "services/openchamber/ui_password";
assert lib.all (
  host: !(systems.${host}.config.sops.secrets ? "services/openchamber/ui_password")
) clientHosts;
assert lib.all (
  host: systems.${host}.config.sops.secrets ? "services/openchamber/devices/${host}/ssh_key"
) clientHosts;
assert lib.all (
  key: lib.hasInfix "restrict,command=" key && !lib.hasInfix "environment=" key
) authorizedKeys;
assert lib.all (key: lib.hasInfix "openchamber-mint" key) authorizedKeys;
assert builtins.length authorizedKeys == builtins.length clientHosts;
assert lib.all (
  host:
  lib.any (
    key:
    lib.hasInfix "openchamber-mint ${host}\"" key
    && lib.hasInfix serverFeature.devices.${host}.sshPublicKey key
  ) authorizedKeys
) clientHosts;
# The forced-command bootstrap is useless if the device cannot reach port 22 over the mesh.
assert lib.all (
  host:
  lib.any (
    rule:
    lib.hasInfix server.my.topology.hosts.${host}.wireguardIpv4 rule
    && lib.hasInfix ''iifname "${meshInterface}"'' rule
    && lib.hasInfix "tcp dport 22" rule
  ) sshRules
) clientHosts;
# Every rule for the listener is a WireGuard rule; no `iifname != "wireguard"` rule exists, so the
# port is not reachable from the internet or the LAN.
assert lib.all (rule: lib.hasInfix ''iifname "${meshInterface}"'' rule) rulesForEndpoint;
assert lib.all (
  host:
  lib.any (
    rule: lib.hasInfix server.my.topology.hosts.${host}.wireguardIpv4 rule && lib.hasInfix dport rule
  ) firewallRules
) expectedFromHosts;
pkgs.runCommandLocal "openchamber-devices-check" { } "touch $out"
