{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  cfg = osConfig.my.features.dev.openchamber;
  primary = config.home.username == osConfig.my.user.primary;
  instances = lib.mapAttrsToList (name: peer: {
    id = "nixfiles:${name}";
    nickname = name;
    sshCommand = "ssh -p ${toString peer.sshPort} ${peer.user}@${peer.address}";
    remoteOpenchamber = {
      mode = "external";
      keepRunning = true;
      preferredPort = peer.port;
      bindHost = "127.0.0.1";
    };
    localForward.bindHost = "127.0.0.1";
    portForwards = [ ];
  }) cfg.peers;
  desired = pkgs.writeText "openchamber-settings.json" (
    builtins.toJSON {
      desktopSshInstances = instances;
      desktopHosts = map (instance: {
        inherit (instance) id;
        label = instance.nickname;
        url = "http://127.0.0.1/";
      }) instances;
    }
  );
in
{
  config = lib.mkIf primary {
    home.packages = [
      cfg.packages.desktop
      cfg.packages.server
    ];
    home.activation.openchamber = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${pkgs.python3}/bin/python ${
        builtins.path {
          path = ./reconcile.py;
          name = "openchamber-settings.py";
        }
      } \
        ${lib.escapeShellArg "${config.home.homeDirectory}/.config/openchamber/settings.json"} ${desired}
    '';
  };
}
