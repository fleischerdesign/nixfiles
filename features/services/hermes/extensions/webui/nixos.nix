{ config, lib, pkgs, ... }:
let
  hcfg = config.my.features.services.hermes;
  ecfg = config.my.features.services.hermes.extensions.webui;
  oidc = ecfg.oidc;
  corePkg = pkgs.callPackage ../../package.nix { inherit (pkgs) nodejs_22; };
  agentSrc = pkgs.fetchFromGitHub {
    owner = "NousResearch";
    repo = "hermes-agent";
    rev = "8f8b66d8ac6ed5172daa213b615037cae0ed92f9";
    hash = "sha256-iEsc8oUoGGX1EzpR4tTIFiB5oiUBUG7e+GR1AfNZv8I=";
  };

  mkIfSet = k: v: lib.optional (v != null) "${k}=${v}";

  oidcRedirectUri =
    let
      ep = config.my.endpoints.hermes-webui or { };
    in
    if ep ? proxy && ep.proxy.subdomain != null then
      "https://${ep.proxy.subdomain}.${ep.proxy.domain}/api/auth/oidc/callback"
    else
      null;

  webuiEnv =
    [
      "HERMES_WEBUI_HOST=127.0.0.1"
      "HERMES_WEBUI_PORT=${toString ecfg.port}"
      "HERMES_WEBUI_STATE_DIR=/var/lib/hermes-webui"
      "HERMES_HOME=/var/lib/hermes/.hermes"
      "HERMES_WEBUI_AGENT_DIR=${agentSrc}"
      "HERMES_WEBUI_PYTHON=${corePkg.passthru.pythonEnv}/bin/python3"
      "HERMES_API_URL=http://127.0.0.1:8642"
      "HERMES_WEBUI_DEFAULT_WORKSPACE=${hcfg.workingDirectory}"
      "MNEMOSYNE_EMBEDDING_MODEL=sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
    ]
    ++ mkIfSet "HASS_URL" hcfg.integrations.hass.url
    ++ mkIfSet "PAPERLESS_URL" hcfg.integrations.paperless.url
    ++ mkIfSet "CAMOFOX_URL" hcfg.integrations.camofox.url
    ++ (lib.optionals (hcfg.integrations.camofox.url != null) [
      "CAMOFOX_API_KEY=${config.sops.placeholder.camofox_api_key}"
    ])
    ++ mkIfSet "HERMES_WEBUI_OIDC_ISSUER" oidc.issuer
    ++ mkIfSet "HERMES_WEBUI_OIDC_CLIENT_ID" oidc.clientId
    ++ mkIfSet "HERMES_WEBUI_OIDC_ALLOW_CLAIM" oidc.allowClaim
    ++ mkIfSet "HERMES_WEBUI_OIDC_ALLOW_VALUES" oidc.allowValues
    ++ mkIfSet "HERMES_WEBUI_OIDC_REDIRECT_URI" oidcRedirectUri;
in
{
  options.my.features.services.hermes.extensions.webui = {
    enable = lib.mkEnableOption "Hermes WebUI extension";
    port = lib.mkOption {
      type = lib.types.port;
      default = 8787;
      description = "WebUI listen port.";
    };
    oidc = lib.mkOption {
      type = lib.types.submodule {
        options = {
          issuer = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "OIDC Issuer URL. When null, OIDC is inactive.";
          };
          clientId = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "OIDC Client ID.";
          };
          allowClaim = lib.mkOption {
            type = lib.types.str;
            default = "email";
            description = "OIDC claim for access validation.";
          };
          allowValues = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Comma-separated allowed claim values.";
          };
        };
      };
      default = { };
      description = "OIDC authentication configuration for the WebUI.";
    };
  };

  config = lib.mkIf (hcfg.enable && ecfg.enable) {
    assertions = [
      {
        assertion = hcfg.enable;
        message = "hermes.extensions.webui requires hermes.enable.";
      }
    ];

    sops.secrets.camofox_api_key = lib.mkIf (hcfg.integrations.camofox.url != null) {
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
        Environment = webuiEnv;
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
