{
  config,
  lib,
  pkgs,
  ...
}:

{
  config = lib.mkIf config.my.homeManager.modules.sherlock.enable {
    home.packages = [ pkgs.playerctl ];

    programs.sherlock = {
      enable = true;
      systemd.enable = true;

      style = ''
        window {
          border-radius: 12px;
        }
      '';

      launchers = [
        # --- Widgets & Utilities on Startup ---
        {
          name = "Weather";
          type = "weather";
          args.location = "berlin";
          priority = 1;
          home = "OnlyHome"; # Nur beim Start anzeigen
          async = true;
        }
        {
          name = "Music Player";
          type = "audio_sink";
          args = { };
          priority = 1;
          home = "Home";
          async = true;
        }
        {
          name = "Calculator";
          type = "calculation";
          args.capabilities = [
            "calc.math"
            "calc.units"
          ];
          priority = 1;
        }

        # --- Main App Launcher ---
        {
          name = "App Launcher";
          type = "app_launcher";
          args = { };
          priority = 2;
          home = "Home";
        }

        # --- Search-based Launchers ---
        {
          name = "Web Search";
          display_name = "Google Search";
          tag_start = "{keyword}";
          alias = "gg";
          type = "web_launcher";
          args = {
            search_engine = "google";
            icon = "google";
          };
          priority = 100; # Nur bei Alias-Eingabe anzeigen
        }
        {
          name = "Kill Process";
          alias = "kill";
          type = "process";
          args = { };
          priority = 6;
          home = "Search"; # Nur bei Suche anzeigen
        }
      ];
    };
  };
}
