# Personal remote selection. The feature owns mounting; the inventory owns peers.
{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  enabled = osConfig.my.features.system.rclone.enable;
  servers = lib.filterAttrs (_: host: host.hostType == "server") osConfig.my.topology.hosts;
  fleet = (import ../../lib/fleet-configs.nix { inherit lib; }).systems osConfig;
  # key_use_agent selects this key's .pub identity from the existing agent;
  # rclone does not read the private key or fall back to the deploy identity.
  keyFile = "${config.home.homeDirectory}/.ssh/id_rsa";
  ini = pkgs.formats.ini { };
  serverConfig = ini.generate "rclone-sftp.conf" (
    lib.mapAttrs (name: host: {
      type = "sftp";
      host = host.wireguardIpv4;
      user = config.home.username;
      port = fleet.${name}.config.my.contracts.provides.ssh.endpoints.ssh.port;
      key_file = keyFile;
      key_use_agent = true;
      known_hosts_file = "/etc/ssh/ssh_known_hosts";
      host_key_algorithms = "ssh-ed25519";
      shell_type = "none";
      disable_hashcheck = true;
    }) servers
  );
  driveConfig = "${config.xdg.configHome}/rclone/gdrive.conf";
in
{
  config = lib.mkIf enabled {
    my.features.system.rclone = {
      sessionTarget = "graphical-session.target";
      mounts =
        lib.mapAttrs (name: _: {
          remote = "${name}:/";
          configFile = toString serverConfig;
          requiredFiles = [
            "${keyFile}.pub"
            "/etc/ssh/ssh_known_hosts"
          ];
        }) servers
        // {
          gdrive = {
            remote = "gdrive:";
            configFile = driveConfig;
            # Google-native documents open in Chrome, rather than masquerading as
            # editable Office exports. Ordinary files retain their original types.
            extraArgs = [ "--drive-export-formats=link.html" ];
          };
        };
    };
    systemd.user.services = lib.mapAttrs' (name: _: {
      name = "rclone-${name}";
      value = {
        Unit = {
          Wants = [ "gcr-ssh-agent.socket" ];
          After = [ "gcr-ssh-agent.socket" ];
        };
        Service.Environment = [ "SSH_AUTH_SOCK=%t/gcr/ssh" ];
      };
    }) servers;
    home.activation.rcloneConfigDirectory = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${pkgs.coreutils}/bin/install -d -m 0700 ${lib.escapeShellArg "${config.xdg.configHome}/rclone"}
    '';
  };
}
