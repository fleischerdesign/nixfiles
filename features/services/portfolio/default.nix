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
      after = [ "network.target" "postgresql.service" ];

      environment = {
        PORT = "3005";
        NITRO_PORT = "3005";
        NODE_ENV = "production";
        
        # Database URL for Drizzle/Libsql (Absolute Path)
        NUXT_DB_URL = "file:/var/lib/portfolio/.data/db.sqlite";
        
        # Plausible Integration
        NUXT_PUBLIC_PLAUSIBLE_API_HOST = "https://plausible.mky.ancoris.ovh";
        
        # Puppeteer runtime fix: Use system chromium
        PUPPETEER_EXECUTABLE_PATH = "${pkgs.chromium}/bin/chromium";
      };

      serviceConfig = {
        # Use the package from the flake input
        ExecStart = "${inputs.portfolio.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/portfolio";
        User = "portfolio";
        Group = "portfolio";
        
        # Persistent state directory
        StateDirectory = "portfolio";
        WorkingDirectory = "/var/lib/portfolio";
        
        Restart = "always";
        # Load all variables from the .env backup
        EnvironmentFile = config.sops.secrets.portfolio_env.path;
      };
    };

    # Ensure all required data directories exist
    systemd.tmpfiles.rules = [
      "d /var/lib/portfolio 0750 portfolio portfolio -"
      "d /var/lib/portfolio/.data 0750 portfolio portfolio -"
      "d /var/lib/portfolio/.data/applications 0750 portfolio portfolio -"
      "d /var/lib/portfolio/.data/content 0750 portfolio portfolio -"
      "d /var/lib/portfolio/.data/uploads 0750 portfolio portfolio -"
      
      # Link migrations from the store to the working directory
      "d /var/lib/portfolio/server 0750 portfolio portfolio -"
      "d /var/lib/portfolio/server/db 0750 portfolio portfolio -"
      "L+ /var/lib/portfolio/server/db/migrations - - - - ${inputs.portfolio.packages.${pkgs.stdenv.hostPlatform.system}.default}/lib/portfolio/server/db/migrations"
    ];

    # Define user and group
    users.users.portfolio = {
      isSystemUser = true;
      group = "portfolio";
      home = "/var/lib/portfolio";
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