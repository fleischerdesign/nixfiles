# features/desktop/webapps/default.nix — Declarative PWA / WebApp launcher generator module
{ lib, ... }:
let
  appSubmodule =
    { name, ... }:
    {
      options = {
        displayName = lib.mkOption {
          type = lib.types.str;
          description = "Human-readable display name for the WebApp desktop entry.";
        };

        url = lib.mkOption {
          type = lib.types.str;
          description = "Target Web Application URL.";
        };

        browser = lib.mkOption {
          type = lib.types.enum [
            "chrome"
            "brave"
            "firefox"
            "epiphany"
          ];
          default = "chrome";
          description = "Browser engine to launch the web application.";
        };

        icon = lib.mkOption {
          type = lib.types.either lib.types.str (lib.types.either lib.types.path lib.types.package);
          default = "internet-web-browser";
          description = "Icon name, path to local image file, or fetched package derivation.";
        };

        comment = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Comment / tooltip description for the desktop launcher.";
        };

        categories = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "Network"
          ];
          description = "XDG Desktop Categories for launcher filtering.";
        };

        wmClass = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "Custom Wayland / X11 window class for WM rules.";
        };

        isolated = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "If true, creates an isolated browser user-data-dir session profile.";
        };

        extraArgs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Additional CLI flags passed to the browser executable.";
        };
      };
    };
in
{
  options.my.features.desktop.webapps = {
    enable = lib.mkEnableOption "Declarative PWA / WebApp launcher feature module";
  };

  config = {
    home-manager.sharedModules = [
      (
        {
          config,
          lib,
          pkgs,
          osConfig ? { },
          ...
        }:
        let
          userCfg = config.my.features.desktop.webapps;
          role = osConfig.my.role or "server";

          buildLauncher =
            appName: appCfg:
            let
              browserBin =
                if appCfg.browser == "chrome" then
                  "${pkgs.google-chrome}/bin/google-chrome-stable"
                else if appCfg.browser == "brave" then
                  "${pkgs.brave}/bin/brave"
                else if appCfg.browser == "firefox" then
                  "${pkgs.firefox}/bin/firefox"
                else if appCfg.browser == "epiphany" then
                  "${pkgs.epiphany}/bin/epiphany"
                else
                  "${pkgs.google-chrome}/bin/google-chrome-stable";

              profileArg =
                if appCfg.isolated then [ "--user-data-dir=\${HOME}/.config/webapps/${appName}" ] else [ ];

              browserArgs =
                if appCfg.browser == "firefox" then
                  [
                    "--new-window"
                    appCfg.url
                  ]
                  ++ appCfg.extraArgs
                else if appCfg.browser == "epiphany" then
                  [
                    "--application-mode"
                    appCfg.url
                  ]
                  ++ appCfg.extraArgs
                else
                  # Chromium-based (Chrome, Brave, etc.)
                  [
                    "--app=${appCfg.url}"
                    "--class=${appCfg.wmClass}"
                    "--name=${appCfg.wmClass}"
                  ]
                  ++ profileArg
                  ++ appCfg.extraArgs;

              execStr = "${browserBin} " + lib.concatStringsSep " " browserArgs;

              isPathIcon = builtins.isPath appCfg.icon || lib.isDerivation appCfg.icon;

              iconName = if isPathIcon then "webapp-${appName}" else appCfg.icon;

              desktopItem = pkgs.makeDesktopItem {
                name = "webapp-${appName}";
                desktopName = appCfg.displayName;
                exec = execStr;
                icon = iconName;
                comment = appCfg.comment;
                categories = appCfg.categories;
                type = "Application";
                terminal = false;
              };
            in
            pkgs.stdenv.mkDerivation {
              name = "webapp-package-${appName}";
              desktopItems = [ desktopItem ];
              nativeBuildInputs = [ pkgs.copyDesktopItems ];
              dontUnpack = true;
              dontBuild = true;

              installPhase = ''
                runHook preInstall
                mkdir -p $out/share/applications
                copyDesktopItems
                ${lib.optionalString isPathIcon ''
                  mkdir -p $out/share/icons/hicolor/512x512/apps
                  cp -L ${appCfg.icon} $out/share/icons/hicolor/512x512/apps/webapp-${appName}.png
                ''}
                runHook postInstall
              '';
            };
        in
        {
          options.my.features.desktop.webapps = {
            enable = lib.mkEnableOption "Declarative PWA / WebApp desktop entry manager";

            defaultBrowser = lib.mkOption {
              type = lib.types.enum [
                "chrome"
                "brave"
                "firefox"
                "epiphany"
              ];
              default = "chrome";
              description = "Default browser engine used for web applications.";
            };

            apps = lib.mkOption {
              type = lib.types.attrsOf (lib.types.submodule appSubmodule);
              default = { };
              description = "Attrset of declarative web application definitions.";
            };
          };

          config = lib.mkIf (userCfg.enable && role != "server") {
            home.packages = lib.mapAttrsToList buildLauncher userCfg.apps;
          };
        }
      )
    ];
  };
}
