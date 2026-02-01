{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.cloudflare-dyndns;
in
{
  options.my.features.services.cloudflare-dyndns = {
    enable = lib.mkEnableOption "Cloudflare Dynamic DNS";
    domains = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of domains/subdomains to update (e.g. ['home.example.com'])";
    };
  };

  config = lib.mkIf cfg.enable {
    # Secret definition (uses defaultSopsFile from common system module)
    sops.secrets.cloudflare_api_token = { };

    services.cloudflare-dyndns = {
      enable = true;
      apiTokenFile = config.sops.secrets.cloudflare_api_token.path;
      domains = cfg.domains;
      # Update every 5 minutes
      frequency = "*:0/5"; 
    };
  };
}
