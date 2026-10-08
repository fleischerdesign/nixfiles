{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  system = osConfig.my.features.dev.opencodex;
  cfg = config.my.features.dev.opencodex;
  codexHome = "${config.home.homeDirectory}/.codex";
  proxyHome = "${config.home.homeDirectory}/.opencodex";
  initialServiceState = pkgs.writeText "opencodex-service-state.json" (
    builtins.toJSON {
      # Version 1 is upstream's platform-neutral record; version 2 requires a Windows backend.
      version = 1;
      inherit codexHome;
      opencodexHome = proxyHome;
      launcherPath = "${config.home.profileDirectory}/bin/ocx";
    }
  );
  initialConfig = pkgs.writeText "opencodex-initial-config.json" (
    builtins.toJSON {
      port = system.port;
      hostname = "127.0.0.1";
      defaultProvider = "openai";
      providers = {
        openai = {
          adapter = "openai-responses";
          baseUrl = "https://chatgpt.com/backend-api/codex";
          authMode = "forward";
          codexAccountMode = "direct";
        };
      }
      // cfg.initialProviders;
      claudeCode = {
        enabled = false;
        intercept.enabled = false;
      };
      codexAutoStart = false;
      codexShimAutoRestore = false;
    }
  );
  credentials = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: path: ''
      ${name}="$(< ${lib.escapeShellArg path})"
      export ${name}
    '') system.credentialFiles
  );
  launcher = pkgs.writeShellScript "opencodex-start" ''
    set -euo pipefail
    umask 077
    mkdir -p "$CODEX_HOME" "$OPENCODEX_HOME"
    # The systemd registration and its matching homes are owned by Home Manager.
    # Upstream requires this record even when its own service installer is not used.
    if [ ! -e "$OPENCODEX_HOME/service-state.json" ]; then
      install -m 600 ${initialServiceState} "$OPENCODEX_HOME/service-state.json"
    fi
    # Codex and OpenCodex own these files. Never overwrite an existing profile.
    if [ ! -e "$CODEX_HOME/config.toml" ]; then
      touch "$CODEX_HOME/config.toml"
    fi
    if [ ! -e "$OPENCODEX_HOME/config.json" ]; then
      install -m 600 ${initialConfig} "$OPENCODEX_HOME/config.json"
    fi
    ${pkgs.jq}/bin/jq -e '(.hostname // "127.0.0.1") == "127.0.0.1"' \
      "$OPENCODEX_HOME/config.json" > /dev/null
    ${credentials}
    exec ${pkgs.custom.opencodex}/bin/ocx start --port ${toString system.port}
  '';
in
{
  options.my.features.dev.opencodex = {
    enable = lib.mkEnableOption "OpenCodex for this user";
    initialProviders = lib.mkOption {
      type = lib.types.attrsOf lib.types.attrs;
      default = { };
      description = "Provider defaults for a new profile; use environment references for keys. Existing profiles remain dashboard-owned.";
    };
  };
  config = lib.mkIf (system.enable && cfg.enable) {
    assertions = [
      {
        assertion = config.my.features.dev.codex.enable;
        message = "OpenCodex requires Codex for the same user.";
      }
    ];
    home.packages = [ pkgs.custom.opencodex ];
    home.sessionVariables = {
      CODEX_HOME = codexHome;
      OPENCODEX_HOME = proxyHome;
    };
    systemd.user.services.opencodex-proxy = {
      Unit = {
        Description = "OpenCodex local provider proxy";
        After = [ "dbus.socket" ];
      };
      Service = {
        Type = "simple";
        ExecStart = launcher;
        ExecStartPost = "${pkgs.custom.opencodex}/bin/ocx ready --wait --timeout 45";
        Restart = "on-failure";
        RestartSec = 5;
        TimeoutStartSec = 60;
        TimeoutStopSec = 30;
        UMask = "0077";
        Environment = [
          "CODEX_HOME=${codexHome}"
          "OPENCODEX_HOME=${proxyHome}"
          "OCX_SERVICE=1"
          "OCX_SERVICE_MANAGED=1"
          "PATH=${
            lib.makeBinPath [
              osConfig.my.features.dev.codex.package
              pkgs.coreutils
              pkgs.git
              pkgs.openssh
              pkgs.procps
              pkgs.systemd
              pkgs.xdg-utils
            ]
          }"
        ];
      };
      Install.WantedBy = [ "default.target" ];
    };
    xdg.desktopEntries.opencodex = {
      name = "OpenCodex";
      genericName = "Provider dashboard";
      exec = "${pkgs.custom.opencodex}/bin/ocx gui";
      icon = "${pkgs.custom.opencodex}/lib/opencodex/gui/dist/logo.png";
      categories = [ "Development" ];
      terminal = false;
    };
  };
}
