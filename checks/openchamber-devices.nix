# The Nix device allowlist, the client configuration and the firewall must agree across hosts.
# A mismatch is not visible on either host alone: a client that is enabled without an allowlist entry
# cannot mint, and a server whose firewall excludes the ingress answers 502. This check names both.
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
  ingressHost = server.my.topology.ingressHost;
  ingressAddress = server.my.topology.hosts.${ingressHost}.wireguardIpv4;
  endpoint = server.my.contracts.provides.openchamber.endpoints.web;
  publication = server.my.contracts.provides.openchamber.publications.web;
  firewallRules = lib.splitString "\n" server.networking.firewall.extraInputRules;
  authorizedKeys = server.users.users.openchamber-bootstrap.openssh.authorizedKeys.keys;
in
assert
  clientHosts == [
    "hom-wrk-01"
    "mob-nb-01"
  ];
assert lib.attrNames serverFeature.devices == clientHosts;
assert lib.all (host: serverFeature.devices.${host}.sshPublicKey != "") clientHosts;
assert lib.all (
  host: systems.${host}.config.my.features.dev.openchamber.client.deviceId == host
) clientHosts;
assert lib.all (
  host:
  systems.${host}.config.my.features.dev.openchamber.client.serverHost == "cld-ops-01"
  && systems.${host}.config.my.features.dev.openchamber.client.serverUrl == publication.publicUrl
) clientHosts;
assert publication.publicUrl == "https://openchamber.vyrx.de";
assert publication.auth == "none" && publication.publicExempt != null;
assert endpoint.directAccess.enable;
assert endpoint.directAccess.interface == "wireguard";
assert endpoint.directAccess.fromHosts == [ ingressHost ];
assert lib.all (
  host: !(server.sops.secrets ? "services/openchamber/devices/${host}/ssh_key")
) clientHosts;
assert server.sops.secrets ? "services/openchamber/ui_password";
assert lib.all (
  host: !(systems.${host}.config.sops.secrets ? "services/openchamber/ui_password")
) clientHosts;
assert lib.all (
  key: lib.hasInfix "restrict,command=" key && !lib.hasInfix "environment=" key
) authorizedKeys;
assert lib.all (key: lib.hasInfix "openchamber-mint" key) authorizedKeys;
assert lib.any (
  rule:
  lib.hasInfix "ip saddr" rule
  && lib.hasInfix ingressAddress rule
  && lib.hasInfix "tcp dport ${toString endpoint.port}" rule
) firewallRules;
assert
  !lib.any (
    rule:
    lib.hasInfix "tcp dport ${toString endpoint.port}" rule
    && lib.hasInfix server.my.topology.hosts.hom-wrk-01.wireguardIpv4 rule
  ) firewallRules;
pkgs.runCommandLocal "openchamber-devices-check" { } "touch $out"
