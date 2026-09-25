# roles/base.nix
# Base system configurations applicable to all hosts (servers and personal computers).
{
  config,
  lib,
  ...
}:
{
  my.features = {
    system = {
      common.enable = lib.mkDefault true;
      bootloader = {
        enable = lib.mkDefault true;
        provider = lib.mkDefault "systemd-boot";
      };
      kernel.enable = lib.mkDefault true;
      fish-shell.enable = lib.mkDefault true;
      networking = {
        wireguard.enable = lib.mkDefault true;
        ssh.enable = lib.mkDefault true;
        # One firewall, rendered: the nftables implementation takes every declaration - the mesh's
        # forwarding rules, the endpoints' exposure, the zones' transit - and applies them as one
        # ruleset. Nothing in this fleet writes a shell command into the firewall any more.
        firewall.enable = lib.mkDefault true;
        # Every host in this fleet is a mesh node and resolves through the resolver in the
        # inventory, never through whatever a network hands it. Which doors it uses is derived
        # from its zone, not written here.
        resolver.enable = lib.mkDefault true;
        # A node that finds itself inside the home LAN uses it, for names and for addresses - the
        # module decides whether that can apply to this host from its zone.
        lan-preference.enable = lib.mkDefault true;
      };
      security.enable = lib.mkDefault true;
      theme.enable = lib.mkDefault true;
    };
  };

  # Credentials shared across hosts (consumed by pi/agents)
  sops.secrets."ai/deepseek_api_key" = lib.mkDefault { };
  sops.secrets."ai/openrouter_api_key" = lib.mkDefault { };
  sops.secrets."ai/opencode_api_key" = lib.mkDefault { };

  nod = {
    enable = lib.mkDefault true;
    targetHost = lib.mkDefault (
      config.my.topology.hosts.${config.networking.hostName}.wireguardIpv4
        or config.my.topology.hosts.${config.networking.hostName}.wireguardIpv4
          or config.networking.hostName
    );
    role = lib.mkDefault config.my.role;
    tags = lib.mkDefault [ ];
    ssh = {
      user = lib.mkDefault "root";
      # The fleet deploy key, not ~/.ssh/deploy-key: that path is a symlink to the node tunnel
      # secret, a service credential whose lifetime belongs to the tunnel feature. Pointing the
      # deployment tooling at it made a service secret the fleet's root credential.
      identityFile = lib.mkDefault "~/.ssh/nixfiles-deploy-key";
    };
    healthChecks = {
      enable = lib.mkDefault true;
      systemd = {
        checkRunning = lib.mkDefault true;
        checkFailedUnits = lib.mkDefault true;
      };
    };
  };
}
