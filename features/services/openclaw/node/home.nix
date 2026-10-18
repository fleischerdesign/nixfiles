{
  endpoint,
  camera,
  webapps,
}:
{
  config,
  lib,
  pkgs,
  inputs,
  osConfig,
  ...
}:
let
  package = inputs.openclaw.packages.${pkgs.stdenv.hostPlatform.system}.openclaw-gateway;
  stateDir = "${config.xdg.stateHome}/openclaw-node";
  hasDesktop = lib.elem "graphical" osConfig.my.user.profiles;
  nodeConfig = pkgs.writeText "openclaw-node.json" (
    builtins.toJSON (
      {
        nodeHost = {
          workerRuns.enabled = true;
          browserProxy = {
            enabled = true;
            allowProfiles = [ "openclaw" ] ++ lib.optional hasDesktop "user";
          };
        };
        browser = {
          enabled = true;
          executablePath = lib.getExe (if hasDesktop then pkgs.google-chrome else pkgs.chromium);
          defaultProfile = "openclaw";
          profiles = {
            openclaw.cdpPort = 18800;
          }
          // lib.optionalAttrs hasDesktop {
            user = {
              driver = "existing-session";
              attachOnly = true;
              userDataDir = "${config.xdg.configHome}/google-chrome";
            };
          };
        }
        // lib.optionalAttrs (!hasDesktop) { headless = true; };
      }
      // lib.optionalAttrs camera {
        # The Linux node plugin keeps camera capture off by default, so the node
        # advertises camera.list/snap/clip only once this is on and FFmpeg is on the
        # service's PATH.
        plugins.entries."linux-node".config.camera.enabled = true;
      }
    )
  );
  # Both enrollment and the daemon use these paths. Never inherit another
  # profile's config, workspace or gateway credentials from the invoking shell.
  environment = ''
    unset OPENCLAW_HOME OPENCLAW_PROFILE OPENCLAW_GATEWAY_TOKEN OPENCLAW_GATEWAY_PASSWORD
    export OPENCLAW_STATE_DIR=${lib.escapeShellArg stateDir}
    export OPENCLAW_CONFIG_PATH=${lib.escapeShellArg "${stateDir}/openclaw.json"}
    export OPENCLAW_WORKSPACE_DIR=${lib.escapeShellArg "${stateDir}/workspace"}
    umask 077
    ${pkgs.coreutils}/bin/install -d -m 0700 "$OPENCLAW_STATE_DIR"
    cd "$OPENCLAW_STATE_DIR"
  '';
  cli = pkgs.writeShellScriptBin "openclaw-node" ''
    set -euo pipefail
    ${environment}
    exec ${package}/bin/openclaw "$@"
  '';
  arguments = lib.escapeShellArgs (
    [
      "node"
      "run"
      "--host"
      endpoint.host
      "--port"
      (toString endpoint.port)
    ]
    ++ lib.optional endpoint.tls "--tls"
  );
  # connect stays in the foreground after enrollment. Stop it with Ctrl-C once
  # paired; the EXIT trap restarts the HM service using the saved device token.
  # Do not use connect --service: Home Manager owns this unit.
  connect = pkgs.writeShellScriptBin "openclaw-node-connect" ''
    set -euo pipefail
    if [ "$#" -ne 1 ]; then
      echo 'Usage: openclaw-node-connect <join-url-or-setup-code>' >&2
      echo ${
        lib.escapeShellArg (
          if endpoint.publicUrl != null then
            "Create a join URL on the gateway for ${endpoint.publicUrl}."
          else
            "Use a setup code for ${endpoint.host}:${toString endpoint.port} (plaintext mesh)."
        )
      } >&2
      exit 2
    fi
    ${environment}
    ${pkgs.systemd}/bin/systemctl --user stop openclaw-node.service
    trap '${pkgs.systemd}/bin/systemctl --user restart openclaw-node.service' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    ${cli}/bin/openclaw-node connect "$1"
  '';
in
{
  config = lib.mkIf (config.home.username == osConfig.my.user.primary) {
    home.packages = [
      cli
      connect
    ]
    # FFmpeg performs the V4L2 capture and reads the Pulse source for clip audio. The
    # headless build disables libpulse, so the regular build is the one that works.
    ++ lib.optionals camera [ pkgs.ffmpeg ];

    # Only this feature's isolated JSON is declarative. Enrollment identity and
    # paired-device credentials remain runtime-owned inside OPENCLAW_STATE_DIR.
    home.file."${stateDir}/openclaw.json".source = nodeConfig;

    # The Control UI launcher, projected by the feature that knows the gateway
    # endpoint, so the published domain is never written a second time.
    my.features.desktop.webapps.apps = webapps;

    systemd.user.services.openclaw-node = {
      Unit = {
        Description = "OpenClaw native session node";
        StartLimitIntervalSec = 0;
        X-Restart-Triggers = [ nodeConfig ];
      };
      Service = {
        ExecStart = "${cli}/bin/openclaw-node ${arguments}";
        Restart = "always";
        RestartSec = 30;
        UMask = "0077";
        Environment = [
          "PATH=${config.home.profileDirectory}/bin:/run/current-system/sw/bin"
        ];
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
