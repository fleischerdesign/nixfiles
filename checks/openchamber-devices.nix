# The device allowlists, the desktop-native listeners and the firewalls must agree across hosts.
# A mismatch is not visible on any single host: a client without a peer key cannot mint, a peer whose
# mesh source is missing from the firewall cannot reach the listener, and a second engine on a
# desktop would duplicate the project store. This check names each of those.
{
  lib,
  pkgs,
  self,
  ...
}:
let
  systems = self.nixosConfigurations;
  clientHosts = lib.attrNames (
    lib.filterAttrs (_: host: host.config.my.features.dev.openchamber.client.enable or false) systems
  );
  server = systems.cld-ops-01.config;
  serverFeature = server.my.features.dev.openchamber.server;
  centralEndpoint = server.my.contracts.provides.openchamber.endpoints.web;
  meshInterface = server.my.features.system.networking.wireguard.interfaceName;

  client = host: systems.${host}.config.my.features.dev.openchamber.client;
  clientConfig = host: systems.${host}.config;
  otherClient = host: lib.findFirst (name: name != host) null clientHosts;

  firewallRules = host: lib.splitString "\n" (clientConfig host).networking.firewall.extraInputRules;
  dport = port: "tcp dport ${toString port}";
  rulesFor =
    host:
    lib.filter (rule: lib.hasInfix (dport (client host).networkAccess.port) rule) (firewallRules host);
  mintConfig =
    host:
    builtins.fromJSON (
      builtins.readFile (clientConfig host).environment.etc."openchamber/mint.json".source
    );
  authorizedKeys =
    host: (clientConfig host).users.users.openchamber-bootstrap.openssh.authorizedKeys.keys;
  expectedUrl =
    host:
    "http://${
      server.my.topology.hosts.${host}.wireguardIpv4
    }:${toString (clientConfig host).my.contracts.provides.openchamber.endpoints.web.port}";
in
assert
  clientHosts == [
    "hom-wrk-01"
    "mob-nb-01"
  ];
# The central server admits both clients from one declared key map; no host repeats the key.
assert lib.attrNames serverFeature.devices == clientHosts;
assert lib.all (
  host:
  serverFeature.devices.${host}.sshPublicKey
  == server.my.features.dev.openchamber.server.deviceKeys.${host}
) clientHosts;
# One engine per host: the desktops use the embedded native listener, never a headless server.
assert lib.all (host: !(clientConfig host).my.features.dev.openchamber.server.enable) clientHosts;
assert lib.all (host: (client host).networkAccess.enable) clientHosts;
assert lib.all (host: (client host).networkAccess.port == 7337) clientHosts;
# Each chooser has its own local instance (upstream-owned, not in this list), the other desktop and
# the central server. The local host never appears as a remote entry.
assert lib.all (
  host:
  let
    remote = (client host).remoteHosts;
    ids = map (entry: entry.id) remote;
    peer = otherClient host;
  in
  ids == [
    "cld-ops-01"
    peer
  ]
  &&
    (lib.findFirst (entry: entry.id == "cld-ops-01") null remote).url
    == "http://${server.my.topology.hosts.cld-ops-01.wireguardIpv4}:${toString centralEndpoint.port}"
  && (lib.findFirst (entry: entry.id == peer) null remote).url == expectedUrl peer
) clientHosts;
# The native listener contract admits exactly the peer desktop over WireGuard, with no publication.
assert lib.all (
  host:
  let
    contract = (clientConfig host).my.contracts.provides.openchamber;
    endpoint = contract.endpoints.web;
  in
  contract.publications == { }
  && endpoint.directAccess.enable
  && endpoint.directAccess.interface == "wireguard"
  && endpoint.directAccess.from == [ ]
  && endpoint.directAccess.fromHosts == [ (otherClient host) ]
) clientHosts;
# The firewall has no LAN or internet rule for the native listener, and the peer's mesh address is
# present on the WireGuard rule. A laptop that never joins the mesh therefore has no door.
assert lib.all (
  host:
  let
    rules = rulesFor host;
    peerAddress = server.my.topology.hosts.${otherClient host}.wireguardIpv4;
  in
  rules != [ ]
  && lib.all (rule: lib.hasInfix ''iifname "${meshInterface}"'' rule) rules
  && lib.any (rule: lib.hasInfix peerAddress rule) rules
  && !(lib.elem (client host).networkAccess.port (clientConfig host)
  .networking.firewall.allowedTCPPorts)
) clientHosts;
# The forced-command helper signs in over loopback and only admits the peer id; the password is a
# separate reader of the same SOPS file, never the central server's secret.
assert lib.all (
  host:
  let
    local = client host;
    bootstrap = (clientConfig host).sops.secrets.${local.networkAccess.bootstrapPasswordSecret};
    user = (clientConfig host).sops.secrets.${local.networkAccess.uiPasswordSecret};
  in
  mintConfig host == {
    serverUrl = "http://127.0.0.1:${toString local.networkAccess.port}";
    passwordFile = bootstrap.path;
    allowlistFile = "/etc/openchamber/bootstrap-devices";
  }
  && bootstrap.owner == "root"
  && bootstrap.group == "openchamber-bootstrap"
  && bootstrap.mode == "0440"
  && user.owner == (clientConfig host).my.user.primary
  && user.mode == "0400"
  &&
    local.networkAccess.uiPasswordSopsFile
    != server.sops.secrets.${serverFeature.uiPasswordSecret}.sopsFile
  && !((clientConfig host).sops.secrets ? ${serverFeature.uiPasswordSecret})
) clientHosts;
assert lib.all (
  host:
  let
    keys = authorizedKeys host;
    peer = otherClient host;
  in
  builtins.length keys == 1
  && lib.all (key: lib.hasInfix "restrict,command=" key && !lib.hasInfix "environment=" key) keys
  && lib.any (
    key:
    lib.hasInfix "openchamber-mint ${peer}" key && lib.hasInfix serverFeature.deviceKeys.${peer} key
  ) keys
) clientHosts;
# Central: a mesh-only listener and a second engine is not declared there.
assert centralEndpoint.directAccess.enable;
assert centralEndpoint.directAccess.interface == "wireguard";
assert server.my.contracts.provides.openchamber.publications == { };
assert server.services.openchamber.host == server.my.topology.hosts.cld-ops-01.wireguardIpv4;
assert server.services.openchamber.port == centralEndpoint.port;
assert
  server.services.openchamber.uiPasswordFile
  == server.sops.secrets."services/openchamber/ui_password".path;
assert lib.all (host: lib.elem host centralEndpoint.directAccess.fromHosts) clientHosts;
assert lib.elem "mob-ph-01" centralEndpoint.directAccess.fromHosts;
# The bootstrap path itself must remain reachable on the mesh for every client.
assert lib.all (
  host:
  lib.any (
    rule:
    lib.hasInfix server.my.topology.hosts.${host}.wireguardIpv4 rule
    && lib.hasInfix ''iifname "${meshInterface}"'' rule
    && lib.hasInfix "tcp dport 22" rule
  ) (lib.splitString "\n" server.networking.firewall.extraInputRules)
) clientHosts;
pkgs.runCommandLocal "openchamber-devices-check" { } "touch $out"
