# features/services/hermes-webui/default.nix
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.my.features.services.hermes-webui;
  envPath =
    if config.sops.secrets ? hermes_agent_env then
      config.sops.secrets.hermes_agent_env.path
    else
      "/dev/null";
in
{
  options.my.features.services.hermes-webui = {
    enable = lib.mkEnableOption "Hermes WebUI";
    port = lib.mkOption {
      type = lib.types.int;
      default = 8787;
      description = "Port the Hermes WebUI container listens on";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.my.features.services.hermes-agent.enable or false;
        message = "hermes-webui requires hermes-agent to be enabled on the same host.";
      }
    ];

    systemd.services.hermes-webui = {
      description = "Hermes WebUI container service";
      wantedBy = [ "multi-user.target" ];
      after = [
        "docker.service"
        "hermes-agent.service"
      ];
      requires = [ "docker.service" ];

      preStart = ''
        ${pkgs.docker}/bin/docker pull ghcr.io/nesquena/hermes-webui:latest || true
        ${pkgs.docker}/bin/docker rm -f hermes-webui || true
        mkdir -p /run/hermes-webui
        # Filter out environment variables starting with a digit (invalid in POSIX/bash)
        ${pkgs.gnugrep}/bin/grep -vE '^[0-9]' ${envPath} > /run/hermes-webui/env || true
        chmod 600 /run/hermes-webui/env

        # Copy the agent source so that it can be owned by hermes and pass the trust check
        rm -rf /run/hermes-webui/hermes-agent
        cp -r ${inputs.hermes-agent} /run/hermes-webui/hermes-agent
        chown -R hermes:hermes /run/hermes-webui/hermes-agent
        chmod -R u+rwX,go-w /run/hermes-webui/hermes-agent
      '';

      serviceConfig = {
        ExecStart = pkgs.writeShellScript "hermes-webui-start" ''
          HERMES_UID=$(${pkgs.coreutils}/bin/id -u hermes)
          HERMES_GID=$(${pkgs.coreutils}/bin/id -g hermes)
          exec ${pkgs.docker}/bin/docker run \
            --name hermes-webui \
            --rm \
            --network=host \
            -e WANTED_UID="$HERMES_UID" \
            -e WANTED_GID="$HERMES_GID" \
            -e HERMES_WEBUI_PORT=${toString cfg.port} \
            -e HERMES_WEBUI_HOST=127.0.0.1 \
            -e HERMES_API_URL=http://127.0.0.1:8642 \
            -e HERMES_HOME=/home/hermeswebui/.hermes \
            -e HERMES_WEBUI_STATE_DIR=/home/hermeswebui/.hermes/webui \
            -e HERMES_WEBUI_DEFAULT_WORKSPACE=/workspace \
            -e HERMES_WEBUI_AGENT_DIR=/agent \
            -e HERMES_WEBUI_AUTO_INSTALL=1 \
            -e PIP_USER=true \
            -e PYTHONUSERBASE=/python-packages \
            --env-file /run/hermes-webui/env \
            -v /nix/store:/nix/store:ro \
            -v /run/hermes-webui/hermes-agent:/agent \
            -v /var/lib/hermes/webui-venv:/app/venv \
            -v /var/lib/hermes/.hermes:/home/hermeswebui/.hermes \
            -v /var/lib/hermes/workspace:/workspace \
            -v /var/lib/camofox:/var/lib/camofox:ro \
            -v /var/lib/hermes/python-packages:/python-packages \
            ghcr.io/nesquena/hermes-webui:latest
        '';
        ExecStop = "${pkgs.docker}/bin/docker stop -t 10 hermes-webui";
        Restart = "always";
        RestartSec = "10s";
      };
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/hermes/workspace 0750 hermes hermes -"
      "d /var/lib/hermes/webui-venv 0750 hermes hermes -"
    ];

    my.endpoints.hermes-webui = {
      host = config.networking.hostName;
      inherit (cfg) port;
    };
  };
}
