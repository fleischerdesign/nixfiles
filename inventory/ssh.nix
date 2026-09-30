# SSH trust anchors, read through authenticated administrative connections.
{ config, lib, ... }:
let
  hosts = config.my.topology.hosts;
  serverKeys = {
    cld-edge-01 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOuUD5xcFFdBYqRupbwQXNQMCxmWZt7G8GPMdvZD6Mst";
    cld-ops-01 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPb3axFfetVr/Lyu5irXU0/Pyj92XkmqPjRkcV/EBR3b";
    hom-srv-01 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGJTV3C3jnAqCdoSDF8rVGYX42EXW8M9Ib3S+1mu+mrN";
  };
in
{
  programs.ssh.knownHosts = lib.mapAttrs (name: publicKey: {
    inherit publicKey;
    hostNames = [
      name
      hosts.${name}.wireguardIpv4
    ];
  }) serverKeys;
}
