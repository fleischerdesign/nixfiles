{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.authentik.proxy;
in
{
  options.my.features.services.authentik.proxy.enable = lib.mkEnableOption "Authentik Proxy Outpost";

  config = lib.mkIf cfg.enable {
    # Specify the secrets file
    sops.defaultSopsFile = ../../../../secrets/secrets.yaml;

    # Define the secret for the outpost
    sops.secrets."authentik_token" = {
      owner = "authentik-outpost";
    };

    services.authentik-outpost = {
      enable = true;
      type = "proxy";
      protocolConfig = {
        authentik_host = "https://auth.igy.ancoris.ovh";
        authentik_host_browser = "https://auth.igy.ancoris.ovh";
        authentik_insecure_skip_verify = false;
        authentik_token_file = config.sops.secrets."authentik_token".path;
      };
    };
  };
}
