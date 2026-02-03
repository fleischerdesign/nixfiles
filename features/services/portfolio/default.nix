{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.my.features.services.portfolio;
in
{
  options.my.features.services.portfolio = {
    enable = lib.mkEnableOption "Portfolio Website";
  };

  config = lib.mkIf cfg.enable {
    # Systemd Service for the Nuxt Portfolio
    systemd.services.portfolio = {
      description = "Nuxt Portfolio Service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      environment = {
        PORT = "3005";
        NITRO_PORT = "3005";
        NODE_ENV = "production";
        # Path to your SQLite DBs
        DATA_DIR = "/var/lib/portfolio/.data";
        # Puppeteer runtime fix: Use system chromium
        PUPPETEER_EXECUTABLE_PATH = "${pkgs.chromium}/bin/chromium";
      };

      serviceConfig = {
        # Use the package from the flake input
        ExecStart = "${inputs.portfolio.packages.${pkgs.system}.default}/bin/portfolio";
        User = "portfolio";
        Group = "portfolio";
        StateDirectory = "portfolio";
        WorkingDirectory = "/var/lib/portfolio";
        Restart = "always";
        # Load sensitive environment variables from sops
        EnvironmentFile = config.sops.secrets.portfolio_env.path;
      };
    };

    # Define user and group
    users.users.portfolio = {
      isSystemUser = true;
      group = "portfolio";
      home = "/var/lib/portfolio";
      createHome = true;
    };
    users.groups.portfolio = {};

    # Caddy Reverse Proxy
    my.features.services.caddy.exposedServices = {
      "portfolio" = {
        port = 3005;
        fullDomain = "fleischer.design";
      };
    };

    # Secrets
    sops.secrets.portfolio_env = {
      owner = "portfolio";
    };
  };
}
