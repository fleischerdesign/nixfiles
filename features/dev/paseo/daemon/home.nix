# The Paseo daemon as a user service.
#
# On a workstation the agents must run with the user's own credentials, and the desktop app starts
# its daemon in `~/.paseo` anyway. This unit therefore owns exactly that home: the app finds a
# running daemon on the address it expects, and the daemon already knows the fleet.
#
# It listens on every address because the app connects over loopback by default; the system
# firewall still admits the port on the WireGuard interface only.
{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:

let
  daemon = osConfig.my.features.dev.paseo.daemon;
  hostName = osConfig.networking.hostName;
  flake =
    osConfig._module.specialArgs.flake or (throw "paseo home: standalone evaluation is unsupported");
  systems = flake.nixosConfigurations;
  plugins = (import ../plugins.nix { inherit lib; }).findPlugins ../plugins;
  stateDir = "${config.home.homeDirectory}/.paseo";

  peerSet = import ../peers.nix {
    inherit
      lib
      pkgs
      systems
      hostName
      plugins
      stateDir
      ;
    package = daemon.package;
    connectPeers = daemon.connectPeers;
    # Hub enrollment belongs to the daemons that run workflow targets, which are the servers'.
    hub.enable = false;
  };

  environment = [
    "PASEO_HOME=${stateDir}"
    "PASEO_LISTEN=${daemon.listenAddress}:${toString daemon.port}"
    "PASEO_RELAY_ENABLED=${lib.boolToString daemon.relay}"
    # The daemon spawns agent CLIs and reads its own process identity; a user unit starts with a
    # minimal PATH, so the tools it needs are declared rather than inherited.
    "PATH=${lib.makeBinPath runtimePath}"
  ];

  runtimePath = [
    pkgs.procps
    pkgs.git
    pkgs.bashInteractive
    pkgs.nodejs_22
  ]
  ++ lib.optional osConfig.my.features.dev.pi.enable osConfig.my.features.dev.pi.package;
in
{
  config = lib.mkIf (daemon.enable && daemon.scope == "user") {
    systemd.user.services.paseo = {
      Unit = {
        Description = "Paseo daemon";
        After = [ "network-online.target" ];
      };
      Service = {
        ExecStart = "${daemon.package}/bin/paseo daemon run --home ${stateDir}";
        # `Environment=` is the systemd directive; a lowercase key is silently ignored and the
        # daemon then falls back to config.json, which binds loopback and is unreachable by peers.
        Environment = environment;
        Restart = "always";
        RestartSec = 2;
      };
      Install.WantedBy = [ "default.target" ];
    };

    systemd.user.services.paseo-configure = {
      Unit = {
        Description = "Reconcile Paseo peers and plugins";
        After = [ "paseo.service" ];
        Requires = [ "paseo.service" ];
      };
      Service = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = 300;
        ExecStart = "${peerSet.configure}/bin/paseo-configure";
        Environment = environment;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
