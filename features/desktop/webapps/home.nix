# features/desktop/webapps/home.nix - the per-user half of the WebApp launcher feature.
{
  config,
  lib,
  pkgs,
  osConfig ? { },
  ...
}:
let
  browserType = lib.types.enum [
    "chrome"
    "brave"
    "epiphany"
  ];
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
          type = browserType;
          default = userCfg.defaultBrowser;
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
          description = "Create an isolated user-data directory (Chrome and Brave only).";
        };

        extraArgs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Additional CLI flags passed to the browser executable.";
        };
      };
    };

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
        else
          "${pkgs.epiphany}/bin/epiphany";

      browserArgs =
        if appCfg.browser == "epiphany" then
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
          ++ appCfg.extraArgs;

      # A shell wrapper preserves argument boundaries (desktop Exec quoting is
      # not shell quoting) and expands HOME only for Chromium's isolated profile.
      launcher = pkgs.writeShellApplication {
        name = "webapp-${appName}";
        text = ''
          exec ${lib.escapeShellArg browserBin} ${lib.escapeShellArgs browserArgs} ${lib.optionalString appCfg.isolated ''"--user-data-dir=$HOME/.config/webapps/${appName}"''}
        '';
      };

      isPathIcon = builtins.isPath appCfg.icon || lib.isDerivation appCfg.icon;

      iconName = if isPathIcon then "webapp-${appName}" else appCfg.icon;

      desktopItem = pkgs.makeDesktopItem {
        name = "webapp-${appName}";
        desktopName = appCfg.displayName;
        exec = lib.getExe launcher;
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
        mkdir -p $out/bin
        ln -s ${lib.getExe launcher} $out/bin/webapp-${appName}
        copyDesktopItems
        ${lib.optionalString isPathIcon ''
          mkdir -p $out/share/icons/hicolor/512x512/apps
          mkdir -p $out/share/icons/hicolor/scalable/apps
          mkdir -p $out/share/pixmaps
          cp -L ${appCfg.icon} $out/share/icons/hicolor/512x512/apps/webapp-${appName}.png
          cp -L ${appCfg.icon} $out/share/icons/hicolor/scalable/apps/webapp-${appName}.png
          cp -L ${appCfg.icon} $out/share/pixmaps/webapp-${appName}.png
          cp -L ${appCfg.icon} $out/share/pixmaps/${appName}.png
        ''}
        runHook postInstall
      '';
    };
in
{
  options.my.features.desktop.webapps = {
    enable = lib.mkEnableOption "Declarative PWA / WebApp desktop entry manager";

    defaultBrowser = lib.mkOption {
      type = browserType;
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
    assertions = lib.concatLists (
      lib.mapAttrsToList (name: app: [
        {
          assertion =
            !app.isolated
            || lib.elem app.browser [
              "chrome"
              "brave"
            ];
          message = "Webapp ${name}: isolated user-data directories require Chrome or Brave.";
        }
        {
          assertion = builtins.match "[A-Za-z0-9_-]+" name != null;
          message = "Webapp ${name}: names must contain only letters, digits, underscores and hyphens.";
        }
      ]) userCfg.apps
    );
    home.packages = lib.mapAttrsToList buildLauncher userCfg.apps;
  };
}
