# features/dev/openchamber/home.nix - the per-user half of the OpenChamber feature.
{
  config,
  lib,
  pkgs,
  osConfig ? { },
  ...
}:
let
  system = osConfig.my.features.dev.openchamber;

  # The launchers are rebuilt here from the same declarations the system side reads. They are pure
  # derivations of the OpenCode binary, so deriving them again is not a second fact - it is the same
  # fact read where it is used.
  opencodeBinary = "${osConfig.my.features.dev.opencode.package}/bin/opencode";
  withOpenCode =
    name: target:
    pkgs.writeShellScriptBin name ''
      export OPENCODE_BINARY=${lib.escapeShellArg opencodeBinary}
      exec ${target} "$@"
    '';
  web = withOpenCode "openchamber" "${pkgs.custom.openchamber-web}/bin/openchamber";
  desktop = withOpenCode "openchamber-desktop" "${pkgs.custom.openchamber-desktop}/bin/openchamber-desktop";

  # The headless server binds the overlay address: the one address every other mesh node can
  # reach, and the address whose port the endpoint contract opens. It is derived from the
  # inventory, never written here a second time.
  meshAddress =
    (osConfig.my.topology.hosts.${osConfig.networking.hostName} or { }).wireguardIpv4 or null;

  userCfg = config.my.features.dev.openchamber;
in
{
  options.my.features.dev.openchamber.enable = lib.mkEnableOption "OpenChamber for this user";

  config = lib.mkIf (system.enable && userCfg.enable) {
    assertions = [
      {
        assertion = config.my.features.dev.opencode.enable;
        message = "OpenChamber requires OpenCode for the same Home Manager user.";
      }
    ];

    home.packages =
      lib.optionals system.web.enable [ web ] ++ lib.optionals system.desktop.enable [ desktop ];

    # A headless server on the mesh, so the other personal computer reaches this one with the
    # instance switcher. It is a user service, like the OpenCodex proxy: the session owns it, and
    # it needs no privilege of its own.
    systemd.user.services.openchamber = lib.mkIf system.server.enable {
      Unit = {
        Description = "OpenChamber headless server on the mesh";
        # The bind address exists only while the mesh interface is up. A user unit cannot order
        # itself after a system device unit, so a bind that races the interface fails and is
        # retried instead of listening on an address that is not the mesh.
        After = [ "default.target" ];
      };

      Service = {
        ExecStart = "${web}/bin/openchamber serve --foreground --port ${toString system.server.port} --host ${meshAddress} --api-only";
        Environment = [ "OPENCHAMBER_LAN_URL=http://${meshAddress}:${toString system.server.port}" ];
        Restart = "always";
        RestartSec = 5;
      };

      Install.WantedBy = [ "default.target" ];
    };

    xdg.desktopEntries.openchamber = lib.mkIf system.desktop.enable {
      name = "OpenChamber";
      genericName = "Coding workspace";
      exec = "${desktop}/bin/openchamber-desktop";
      icon = "${pkgs.custom.openchamber-desktop}/share/icons/hicolor/scalable/apps/openchamber.svg";
      categories = [ "Development" ];
      terminal = false;
    };
  };
}
