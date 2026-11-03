# The per-user half of the OpenChamber client: wrapper, registry, desktop entry, login autostart and
# session hook.
#
# The registry is token-free and rendered by Nix. The token lives only in OpenChamber's own
# settings.json, which is the only place upstream reads it from. The adapter preserves every key and
# every unmanaged host it did not write.
{
  config,
  lib,
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
        # Bounded: a stale holder must delay a start, never hang it. The entry hook allows 90 s,
        # which leaves room for this wait plus one worst-case host reconciliation. A timeout is
        # deferred (75) rather than fatal: the other holder is either reconciling already or stuck,
        # and neither is a reason to keep the local window shut.
        if flock -w 20 -x 9; then
          exec ${provision}/bin/openchamber-provision
        fi
        echo '{"event":"provision-lock-timeout"}' >&2
        exit 75
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
      pkgs.systemd
    ];
    text = ''
      # Local work is the default substrate: the app starts its in-process server on the declared
      # port. A login shell may still carry the old override from a previous generation.
      unset OPENCHAMBER_SKIP_LOCAL_SERVER
      export OPENCHAMBER_DESKTOP_USER_DATA_DIR="''${XDG_CONFIG_HOME:-$HOME/.config}/OpenChamber"
      export OPENCHAMBER_DESKTOP_PROVISION=${hook}/bin/openchamber-provision-hook
      # Upstream rewrites the autostart entry on every start; name this launcher there so the next
      # login carries the provisioning environment instead of the bare Electron binary.
      autostart_exec="$(readlink -f "$0")"
      export OPENCHAMBER_AUTOSTART_EXEC="$autostart_exec"

      # Provisioning itself runs exactly once, from the package's entry hook (the same hook that
      # covers app.relaunch()). Running it here as well reconciled every host twice per start.
      # The hook needs OPENCHAMBER_DESKTOP_PROVISION, exported above.

      # Reconcile the managed Go accounts at every real start. This is the native user-unit
      # lifecycle of the app, not a filesystem watch: restart is a no-op when nothing changed,
      # retries a previously failed seed now, and picks up a rotated SOPS value. --no-block keeps
      # the launch independent of the seed, which retries the API itself.
      ${pkgs.coreutils}/bin/timeout --signal=KILL 10 \
        ${pkgs.systemd}/bin/systemctl --user restart --no-block openchamber-go-accounts.service \
        || true

      exec ${cfg.desktopPackage}/bin/openchamber-desktop "$@"
    '';
  };

  # The entry upstream's `desktop_set_launch_at_login` toggle and its startup reconcile write. It is
  # installed as a real file (not a store symlink) because the app rewrites it; `--background` keeps
  # the window closed at login while the embedded engine and the tray start. Closing the window then
  # hides it to the tray (`desktopMinimizeToTrayEnabled`), so a login session owns exactly one engine.
  autostartEntry = pkgs.writeText "openchamber-autostart.desktop" ''
    [Desktop Entry]
    Type=Application
    Name=OpenChamber
    Exec=${launch}/bin/openchamber-launch --background
    Terminal=false
    X-GNOME-Autostart-enabled=true
    StartupWMClass=openchamber
  '';
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

  home.activation.openchamberAutostart = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    entry=${lib.escapeShellArg "${config.xdg.configHome}/autostart/openchamber.desktop"}
    ${pkgs.coreutils}/bin/mkdir -p "''${entry%/*}"
    ${pkgs.coreutils}/bin/install -m 0644 ${autostartEntry} "$entry"
  '';

  # A terminal launch and the desktop launcher must reach the same hook. `app.relaunch()` inherits
  # the environment, which is what makes provisioning run again after an in-app relaunch.
  home.sessionVariables = {
    OPENCHAMBER_DESKTOP_USER_DATA_DIR = "${config.xdg.configHome}/OpenChamber";
    OPENCHAMBER_DESKTOP_PROVISION = "${hook}/bin/openchamber-provision-hook";
    # A raw binary launched from a login shell reconciles the autostart entry too; naming the
    # launcher here keeps that rewrite from replacing it with the bare Electron binary.
    OPENCHAMBER_AUTOSTART_EXEC = "${launch}/bin/openchamber-launch";
  };
}
