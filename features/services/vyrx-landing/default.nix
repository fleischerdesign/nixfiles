{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.my.features.services.vyrx-landing;
  vyrxLandingPkg = inputs.vyrx-landing.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  options.my.features.services.vyrx-landing = {
    enable = lib.mkEnableOption "VYRX Enterprise Portal & Landing Page";
  };

  config = lib.mkIf cfg.enable {
    my.contracts.provides.vyrx-landing = {
      endpoints.web = {
        port = 80;
        protocol = "tcp";
        scope = "public";
        auth = "none";
        subdomain = "@";
        publicExempt = "public static landing page, no user data";
        customExtraConfig = ''
          root * ${vyrxLandingPkg}
          file_server
          try_files {path} {path}/index.html =404
        '';
        dashboard = {
          show = false;
        };
      };
    };
  };
}
