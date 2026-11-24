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
  address = osConfig.my.topology.hosts.${osConfig.networking.hostName}.wireguardIpv4 or null;
  file =
    path:
    builtins.path {
      inherit path;
      name = baseNameOf path;
    };
  serverHosts =
    if
      cfg.serverOnlyClients && cfg.defaultHost != null && builtins.hasAttr cfg.defaultHost cfg.serverPeers
    then
      { ${cfg.defaultHost} = cfg.serverPeers.${cfg.defaultHost}; }
    else
      cfg.serverPeers;
  plan = pkgs.writeText "openchamber-fleet.json" (
    builtins.toJSON {
      host = osConfig.networking.hostName;
      peers = if cfg.serverOnlyClients then { } else cfg.peers;
      serverPeers = serverHosts;
    }
  );
  pair = pkgs.writeShellApplication {
    name = "openchamber-fleet-pair";
    runtimeInputs = [ pkgs.openssh ];
    text = ''
      exec ${pkgs.python3}/bin/python ${file ./pair.py} ${plan} "$@"
    '';
  };
  mobilePair = pkgs.writeShellApplication {
    name = "openchamber-mobile-pair";
    text = ''
      exec ${cfg.packages.server}/bin/openchamber connect-url \
        --port ${toString cfg.port} \
        --server ${lib.escapeShellArg "http://${address}:${toString cfg.port}"} \
        --qr "$@"
    '';
  };
  desired = pkgs.writeText "openchamber-settings.json" (
    builtins.toJSON {
      desktopSshInstances = [ ];
      desktopHosts =
        lib.optionals (!cfg.serverOnlyClients) (
          lib.mapAttrsToList (name: peer: {
            id = "nixfiles:${name}";
            label = name;
            url = "http://${peer.address}:${toString peer.port}";
            apiUrl = "http://${peer.address}:${toString peer.port}";
          }) cfg.peers
        )
        ++ lib.mapAttrsToList (name: peer: {
          id = "nixfiles-server:${name}";
          label = name;
          url = "http://${peer.address}:${toString peer.port}";
          apiUrl = "http://${peer.address}:${toString peer.port}";
        }) serverHosts;
      desktopLocalPort = cfg.port;
      desktopLanAccessEnabled = true;
      desktopDefaultHostId =
        if cfg.defaultHost == null then
          "local"
        else if builtins.hasAttr cfg.defaultHost cfg.serverPeers then
          "nixfiles-server:${cfg.defaultHost}"
        else
          "nixfiles:${cfg.defaultHost}";
      desktopUiPasswordPath =
        if cfg.uiPasswordSecret == null then null else osConfig.sops.secrets.${cfg.uiPasswordSecret}.path;
    }
  );
  portCheck = pkgs.writeShellScript "openchamber-port-check" ''
    set -eu
    port=${toString cfg.port}
    for _ in 1 2 3; do
      if ${pkgs.curl}/bin/curl -fsS --max-time 1 "http://127.0.0.1:$port/health" 2>/dev/null \
        | ${pkgs.gnugrep}/bin/grep -Eq '"runtime"[[:space:]]*:[[:space:]]*"(desktop|web)"'; then
        exit 0
      fi
      ${pkgs.coreutils}/bin/sleep 1
    done
    if ${pkgs.iproute2}/bin/ss -ltnH "sport = :$port" | ${pkgs.gnugrep}/bin/grep -q .; then
      echo "OpenChamber: TCP port $port is already in use by another service" >&2
      exit 1
    fi
  '';
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
    ]
    ++ lib.optionals (address != null) [ mobilePair ];

    # The desktop rewrites the autostart entry to its raw Electron path on every start, so the
    # wrapper's environment must also exist in the session. The pinned CLI itself is on PATH via
    # home.packages, not only through the wrapper's runtime path.
    home.sessionVariables = {
      ELECTRON_OZONE_PLATFORM_HINT = "auto";
      CHROME_DEVEL_SANDBOX = "${cfg.packages.desktop}/share/openchamber/chrome-sandbox";
      FLEET_AGENT_PATH = "/run/current-system/sw/bin/fleet-agent";
      FLEET_SSH_PATH = "${pkgs.openssh}/bin/ssh";
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

    systemd.user.services.openchamber-fleet-extension = lib.mkIf (cfg.role != "server") {
      Unit = {
        Description = "Install the Fleet OpenChamber runtime extension";
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "oneshot";
        TimeoutStartSec = 60;
        ExecStart = "${cfg.packages.fleetInstaller}/bin/openchamber-fleet-extension-install --mode desktop --settings-file ${lib.escapeShellArg "${config.xdg.configHome}/openchamber/settings.json"} --extension ${lib.escapeShellArg "${cfg.packages.fleetExtension}"} --timeout 30";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
    systemd.user.timers.openchamber-fleet-extension = lib.mkIf (cfg.role != "server") {
      Unit.Description = "Retry the Fleet runtime extension install when OpenChamber starts";
      Timer = {
        OnStartupSec = "1m";
        OnUnitInactiveSec = "5m";
      };
      Install.WantedBy = [ "timers.target" ];
    };
    home.activation.openchamberPort = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${portCheck}
    '';
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
