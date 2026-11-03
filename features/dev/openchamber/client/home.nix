# The per-user half of the OpenChamber client: wrapper, registry, desktop entry and session hook.
#
# The registry is token-free and rendered by Nix. The token lives only in OpenChamber's own
# settings.json, which is the only place upstream reads it from. The adapter preserves every key and
# every unmanaged host it did not write.
{
  config,
  pkgs,
  osConfig,
  ...
}:

let
  cfg = osConfig.my.features.dev.openchamber.client;

  registry = pkgs.writeText "openchamber-registry.json" (
    builtins.toJSON {
      hosts = [
        {
          id = cfg.deviceId;
          label = cfg.deviceId;
          url = cfg.serverUrl;
          apiUrl = cfg.serverUrl;
          mintCommand = ''
            ${pkgs.openssh}/bin/ssh \
              -i ${cfg.deviceKeyPath} \
              -o IdentitiesOnly=yes \
              -o BatchMode=yes \
              -o PasswordAuthentication=no \
              -o StrictHostKeyChecking=yes \
              -o UserKnownHostsFile=/etc/ssh/ssh_known_hosts \
              -o ConnectTimeout=10 \
              openchamber-bootstrap@${cfg.serverSshAddress}
          '';
        }
      ];
      defaultHostId = cfg.deviceId;
    }
  );

  provision = pkgs.writeShellApplication {
    name = "openchamber-provision";
    runtimeInputs = [ pkgs.nodejs_22 ];
    text = ''
      exec ${pkgs.nodejs_22}/bin/node ${../provision.mjs} \
        --registry ${registry} \
        --state "$HOME/.local/state/openchamber-provision/state.json" \
        --settings "$HOME/.config/openchamber/settings.json" \
        --app-user-data "''${XDG_CONFIG_HOME:-$HOME/.config}/OpenChamber" "$@"
    '';
  };

  provisionLocked = pkgs.writeShellApplication {
    name = "openchamber-provision-locked";
    runtimeInputs = [
      pkgs.util-linux
      pkgs.coreutils
    ];
    text = ''
      lock="''${XDG_RUNTIME_DIR:-$HOME/.run}/openchamber-provision.lock"
      mkdir -p "''${lock%/*}"
      (
        # Bounded: a stale holder must delay a start, never hang it forever. The outer hook allows
        # 60 s, so a lock timeout still ends in a clean, fail-closed exit.
        flock -w 30 -x 9
        ${provision}/bin/openchamber-provision
      ) 9>"$lock"
    '';
  };

  hook = pkgs.writeShellApplication {
    name = "openchamber-provision-hook";
    runtimeInputs = [
      pkgs.util-linux
      pkgs.coreutils
    ];
    text = ''
      export OPENCHAMBER_DESKTOP_USER_DATA_DIR="''${OPENCHAMBER_DESKTOP_USER_DATA_DIR:-''${XDG_CONFIG_HOME:-$HOME/.config}/OpenChamber}"
      exec ${provisionLocked}/bin/openchamber-provision-locked
    '';
  };

  launch = pkgs.writeShellApplication {
    name = "openchamber-launch";
    runtimeInputs = [
      pkgs.util-linux
      pkgs.coreutils
    ];
    text = ''
      export OPENCHAMBER_SKIP_LOCAL_SERVER=1
      export OPENCHAMBER_DESKTOP_USER_DATA_DIR="''${XDG_CONFIG_HOME:-$HOME/.config}/OpenChamber"
      export OPENCHAMBER_DESKTOP_PROVISION=${hook}/bin/openchamber-provision-hook

      rc=0
      ${provisionLocked}/bin/openchamber-provision-locked || rc=$?
      # 75 means another instance already owns the profile; the singleton check below ends this
      # launch normally. Every other failure is shown, not traded for a broken window.
      if [ "$rc" -ne 0 ] && [ "$rc" -ne 75 ]; then
        exit "$rc"
      fi
      exec ${cfg.desktopPackage}/bin/openchamber-desktop "$@"
    '';
  };
in
{
  home.packages = [
    cfg.desktopPackage
    launch
  ];

  xdg.desktopEntries.openchamber = {
    name = "OpenChamber";
    genericName = "OpenCode client";
    comment = "Desktop client for the OpenChamber server";
    exec = "${launch}/bin/openchamber-launch %U";
    icon = "openchamber";
    categories = [ "Development" ];
    terminal = false;
    type = "Application";
    mimeType = [ "x-scheme-handler/openchamber" ];
    startupNotify = true;
  };

  # A terminal launch and the desktop launcher must reach the same hook. `app.relaunch()` inherits
  # the environment, which is what makes provisioning run again after an in-app relaunch.
  home.sessionVariables = {
    OPENCHAMBER_SKIP_LOCAL_SERVER = "1";
    OPENCHAMBER_DESKTOP_USER_DATA_DIR = "${config.xdg.configHome}/OpenChamber";
    OPENCHAMBER_DESKTOP_PROVISION = "${hook}/bin/openchamber-provision-hook";
  };
}
