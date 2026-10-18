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
  # Printed under the usage line, so the helper itself says where a join URL comes from.
  usageHint =
    if endpoint.publicUrl != null then
      "Create a join URL on the gateway for ${endpoint.publicUrl}."
    else
      "Use a setup code for ${endpoint.host}:${toString endpoint.port} (plaintext mesh).";
  # connect stays in the foreground after enrollment. Stop it with Ctrl-C once
  # paired; the EXIT trap restarts the HM service using the saved device token.
  # Do not use connect --service: Home Manager owns this unit.
  #
  # Enrollment needs the unit stopped, because a foreground node and the service share this state
  # directory. Two rules keep that from becoming an outage of its own: only a join URL or setup
  # code reaches the service - usage and flags answer and exit - and the run happens in a
  # transient scope beside the unit, so the stop cannot kill the helper that starts it again.
  # Called from inside the node (an agent's exec host=node) the stop otherwise signals the
  # helper's own shell, and an explicit stop suppresses Restart=always.
  connect = pkgs.writeShellScriptBin "openclaw-node-connect" ''
    set -euo pipefail

    usage() {
      echo 'Usage: openclaw-node-connect <join-url-or-setup-code>'
      echo ${lib.escapeShellArg usageHint}
    }

    case "''${1:-}" in
      -h | --help)
        usage
        exit 0
        ;;
      -*)
        echo "openclaw-node-connect: expected a join URL or setup code, got the flag $1" >&2
        usage >&2
        exit 2
        ;;
      "")
        usage >&2
        exit 2
        ;;
    esac

    if [ "$#" -ne 1 ]; then
      echo 'openclaw-node-connect: expected exactly one join URL or setup code' >&2
      usage >&2
      exit 2
    fi

    # Re-exec in a transient scope: it is a sibling of openclaw-node.service, so the stop below
    # cannot signal this process. The scope keeps the caller's process group, so the foreground
    # connection, its output and Ctrl-C behave as documented.
    if [ -z "''${OPENCLAW_NODE_CONNECT_SCOPED:-}" ]; then
      OPENCLAW_NODE_CONNECT_SCOPED=1
      export OPENCLAW_NODE_CONNECT_SCOPED
      exec ${pkgs.systemd}/bin/systemd-run --user --scope --quiet "$0" "$@"
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
