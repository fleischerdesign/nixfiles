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
  file =
    path:
    builtins.path {
      inherit path;
      name = baseNameOf path;
    };
  plan = pkgs.writeText "openchamber-fleet.json" (
    builtins.toJSON {
      host = osConfig.networking.hostName;
      inherit (cfg) peers;
    }
  );
  pair = pkgs.writeShellApplication {
    name = "openchamber-fleet-pair";
    runtimeInputs = [ pkgs.openssh ];
    text = ''
      exec ${pkgs.python3}/bin/python ${file ./pair.py} ${plan} "$@"
    '';
  };
  desired = pkgs.writeText "openchamber-settings.json" (
    builtins.toJSON {
      desktopSshInstances = [ ];
      desktopHosts = lib.mapAttrsToList (name: peer: {
        id = "nixfiles:${name}";
        label = name;
        url = "http://${peer.address}:${toString peer.port}";
        apiUrl = "http://${peer.address}:${toString peer.port}";
      }) cfg.peers;
      desktopLocalPort = cfg.port;
      desktopLanAccessEnabled = true;
    }
  );
  autostartPath = "${config.xdg.configHome}/autostart/openchamber.desktop";
  # The desktop rewrites this entry on startup (linux-autostart.mjs), so it must be a regular
  # file; a home.file symlink into the read-only store would make that write fail.
  autostartEntry = pkgs.writeText "openchamber-autostart.desktop" ''
    [Desktop Entry]
    Type=Application
    Name=OpenChamber
    Exec=${cfg.packages.desktop}/bin/openchamber-desktop --background
    Terminal=false
    X-GNOME-Autostart-enabled=true
    StartupWMClass=openchamber
  '';
in
{
  config = lib.mkIf primary {
    home.packages = [
      cfg.packages.desktop
      cfg.packages.server
      cfg.packages.opencode
      pair
    ];

    # The desktop rewrites the autostart entry to its raw Electron path on every start, so the
    # wrapper's environment must also exist in the session. The pinned CLI itself is on PATH via
    # home.packages, not only through the wrapper's runtime path.
    home.sessionVariables = {
      ELECTRON_OZONE_PLATFORM_HINT = "auto";
      CHROME_DEVEL_SANDBOX = "${cfg.packages.desktop}/share/openchamber/chrome-sandbox";
    };

    systemd.user.services.openchamber-enrollment = {
      Unit.Description = "Enroll declared OpenChamber desktop peers";
      Service = {
        Type = "oneshot";
        ExecStart = "${pair}/bin/openchamber-fleet-pair";
        Environment = "XDG_CONFIG_HOME=${config.xdg.configHome}";
        TimeoutStartSec = 120;
        UMask = "0077";
      };
    };
    systemd.user.timers.openchamber-enrollment = {
      Unit.Description = "Retry initial OpenChamber enrollment when peers become available";
      Timer = {
        OnStartupSec = "1m";
        OnUnitInactiveSec = "5m";
      };
      Install.WantedBy = [ "timers.target" ];
    };
    home.activation.openchamber = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${pkgs.python3}/bin/python ${file ./reconcile.py} \
        ${lib.escapeShellArg "${config.xdg.configHome}/openchamber/settings.json"} ${desired}
    '';
    home.activation.openchamberAutostart = lib.hm.dag.entryAfter [ "writeBoundary" ] (
      if cfg.autostart then
        ''
          run ${pkgs.coreutils}/bin/install -Dm644 ${autostartEntry} ${lib.escapeShellArg autostartPath}
        ''
      else
        ''
          run ${pkgs.coreutils}/bin/rm -f ${lib.escapeShellArg autostartPath}
        ''
    );
  };
}
