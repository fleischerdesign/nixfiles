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

  # Every entry describes one remote server instance and is named after that server host. The local
  # instance is upstream's built-in entry and is not written here: naming a remote entry after the
  # client is what made it look like a second local instance.
  registry = pkgs.writeText "openchamber-registry.json" (
    builtins.toJSON {
      hosts = map (host: {
        id = host.id;
        label = host.label;
        url = host.url;
        apiUrl = host.url;
        mintCommand = ''
          ${pkgs.openssh}/bin/ssh \
            -i ${cfg.deviceKeyPath} \
            -o IdentitiesOnly=yes \
            -o BatchMode=yes \
            -o PasswordAuthentication=no \
            -o StrictHostKeyChecking=yes \
            -o UserKnownHostsFile=/etc/ssh/ssh_known_hosts \
            -o ConnectTimeout=10 \
            openchamber-bootstrap@${host.sshAddress}
        '';
      }) cfg.remoteHosts;
      # The native listener's declared settings. Only the password path is written here; the
      # adapter reads the secret file and merges the value into the user's 0600 settings file.
      localNetwork =
        if cfg.networkAccess.enable then
          {
            enable = true;
            port = cfg.networkAccess.port;
            uiPasswordFile = osConfig.sops.secrets.${cfg.networkAccess.uiPasswordSecret}.path;
            clientAuthModule = "${pkgs.openchamber.passthru.core}/lib/openchamber/packages/web/server/lib/client-auth/remote-clients.js";
          }
        else
          null;
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
      # Local work is the default substrate: the app starts its in-process server on the declared
      # port. A login shell may still carry the old override from a previous generation.
      unset OPENCHAMBER_SKIP_LOCAL_SERVER
      export OPENCHAMBER_DESKTOP_USER_DATA_DIR="''${XDG_CONFIG_HOME:-$HOME/.config}/OpenChamber"
      export OPENCHAMBER_DESKTOP_PROVISION=${hook}/bin/openchamber-provision-hook

      rc=0
      ${provisionLocked}/bin/openchamber-provision-locked || rc=$?
      # 3/4/5 mean a remote instance is configured but not reachable or not allowed. That must never
      # keep the local window shut: the app probes the remote host at boot and falls back to local.
      # 75 means another instance owns the profile. Only a broken adapter or settings schema (64, 70)
      # is fatal.
      case "$rc" in
        0|3|4|5|75) ;;
        *) exit "$rc" ;;
      esac
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
    OPENCHAMBER_DESKTOP_USER_DATA_DIR = "${config.xdg.configHome}/OpenChamber";
    OPENCHAMBER_DESKTOP_PROVISION = "${hook}/bin/openchamber-provision-hook";
  };
}
