{
  config,
  lib,
  pkgs,
  ...
}:
let
  hcfg = config.my.features.services.hermes;
  ecfg = config.my.features.services.hermes.extensions.webui;
in
{
  options.my.features.services.hermes.extensions.webui = {
    enable = lib.mkEnableOption "Hermes WebUI extension";
    port = lib.mkOption {
      type = lib.types.port;
      default = 8787;
      description = "WebUI listen port.";
    };
    oidcIssuer = lib.mkOption {
      type = lib.types.str;
      default = "https://auth.ancoris.ovh/application/o/moebius";
      description = "OIDC Issuer URL.";
    };
    oidcClientId = lib.mkOption {
      type = lib.types.str;
      default = "moebius-webui";
      description = "OIDC Client ID.";
    };
    oidcAllowClaim = lib.mkOption {
      type = lib.types.str;
      default = "email";
      description = "OIDC claim for access validation.";
    };
    oidcAllowValues = lib.mkOption {
      type = lib.types.str;
      default = "philipp@fleischer.design";
      description = "Comma-separated allowed claim values.";
    };
  };

  config = lib.mkIf (hcfg.enable && ecfg.enable) {
    assertions = [
      {
        assertion = hcfg.enable;
        message = "hermes.extensions.webui requires hermes.enable.";
      }
    ];

    sops.secrets.camofox_api_key = {
      restartUnits = lib.mkAfter [ "hermes-webui.service" ];
    };

    systemd.services.hermes-webui = {
      description = "Hermes WebUI";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "hermes-agent.service"
      ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "simple";
        User = "hermes";
        Group = "hermes";
        ExecStart = "${pkgs.callPackage ./package.nix { }}/bin/hermes-webui";
        Restart = "on-failure";
        StateDirectory = "hermes-webui";
        StateDirectoryMode = "0700";
        UMask = "0077";
        Environment = let
          corePkg = pkgs.callPackage ../../package.nix { inherit (pkgs) nodejs_22; };
          agentSrc = pkgs.fetchFromGitHub {
            owner = "NousResearch";
            repo = "hermes-agent";
            rev = "8f8b66d8ac6ed5172daa213b615037cae0ed92f9";
            hash = "sha256-iEsc8oUoGGX1EzpR4tTIFiB5oiUBUG7e+GR1AfNZv8I=";
          };
        in [
          "HERMES_WEBUI_HOST=127.0.0.1"
          "HERMES_WEBUI_PORT=${toString ecfg.port}"
          "HERMES_WEBUI_STATE_DIR=/var/lib/hermes-webui"
          "HERMES_HOME=/var/lib/hermes/.hermes"
          "HERMES_WEBUI_AGENT_DIR=${agentSrc}"
          "HERMES_WEBUI_PYTHON=${corePkg.passthru.pythonEnv}/bin/python3"
          "HERMES_API_URL=http://127.0.0.1:8642"
          "HERMES_WEBUI_DEFAULT_WORKSPACE=${hcfg.workingDirectory}"
          "HASS_URL=${hcfg.hassUrl}"
          "PAPERLESS_URL=${hcfg.paperlessUrl}"
          "CAMOFOX_URL=${hcfg.camofoxUrl}"
          "CAMOFOX_API_KEY=${config.sops.placeholder.camofox_api_key}"
          "MNEMOSYNE_EMBEDDING_MODEL=sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
          "HERMES_WEBUI_OIDC_ISSUER=${ecfg.oidcIssuer}"
          "HERMES_WEBUI_OIDC_CLIENT_ID=${ecfg.oidcClientId}"
          "HERMES_WEBUI_OIDC_ALLOW_CLAIM=${ecfg.oidcAllowClaim}"
          "HERMES_WEBUI_OIDC_ALLOW_VALUES=${ecfg.oidcAllowValues}"
          "HERMES_WEBUI_OIDC_REDIRECT_URI=https://${
            if
              config.my.endpoints ? hermes-webui && config.my.endpoints.hermes-webui.proxy.subdomain != null
            then
              "${config.my.endpoints.hermes-webui.proxy.subdomain}.${config.my.endpoints.hermes-webui.proxy.domain}"
            else
              "moebius.${config.my.features.services.caddy.baseDomain or "rls.ancoris.ovh"}"
          }/api/auth/oidc/callback"
        ];
        EnvironmentFile = lib.optionals (config.sops.secrets ? hermes_agent_env) [
          config.sops.secrets.hermes_agent_env.path
        ];
      };
    };

    my.endpoints.hermes-webui = {
      host = config.networking.hostName;
      inherit (ecfg) port;
    };
  };
}
