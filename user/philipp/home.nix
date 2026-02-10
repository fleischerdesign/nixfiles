{
  config,
  pkgs,
  inputs,
  osConfig,
  ...
}:

{
  imports = [
    ./packages.nix
    # Other user-specific modules will be imported here as they are refactored
  ];

  home.file.".mozilla/firefox/philipp/chrome/firefox-gnome-theme".source = inputs.firefox-gnome-theme;
  home.file.".thunderbird/philipp/chrome/thunderbird-gnome-theme".source = inputs.thunderbird-gnome-theme;

  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "philipp";
  home.homeDirectory = "/home/philipp";

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "24.05";

  # Let Home Manager install and manage itself.
  systemd.user.startServices = "sd-switch";

  xdg.desktopEntries."ls3d-handler" = {
    name = "WBS Learnspace 3D Handler";
    exec = "/home/philipp/ls3d-handler.sh %u";
    type = "Application";
    terminal = false;
    noDisplay = true;
    mimeType = [ "x-scheme-handler/ls3d" ];
  };

  xdg.mimeApps.defaultApplications = {
    "x-scheme-handler/ls3d" = "ls3d-handler.desktop";
  };

  programs = {
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
    thunderbird = {
      enable = osConfig.my.role != "server";
      profiles.philipp = {
        isDefault = true;
        userChrome = ''
          @import "thunderbird-gnome-theme/userChrome.css";

          /* Fix für die Lücke am unteren Rand (speziell für Niri/Tiling) */
          #tabbrowser-tabpanels, 
          #messengerBox {
            margin-bottom: 0 !important;
          }
        '';
        userContent = ''
          @import "thunderbird-gnome-theme/userContent.css";
        '';
        settings = {
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
          "svg.context-properties.content.enabled" = true;
          "browser.uidensity" = 0;
          "intl.locale.requested" = "de";
        };
      };
    };
    firefox = {
      enable = osConfig.my.role != "server";
      languagePacks = [ "de" ];
      profiles.philipp = {
        search = {
          default = "ddg";
          force = true;
        };
        userChrome = ''
          @import "firefox-gnome-theme/userChrome.css";

          /* Den Lesezeichen-Stern (Star-Button) komplett entfernen */
          #star-button-box {
            display: none !important;
          }
        '';
        userContent = ''
          @import "firefox-gnome-theme/userContent.css";
        '';
        settings = {
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
          "browser.uidensity" = 0;
          "svg.context-properties.content.enabled" = true;
          "browser.theme.dark-private-windows" = false;
          "intl.locale.requested" = "de";
        };
      };
    };
    fish = {
      enable = true;
      shellAliases = {
        c = "codium";
      };
      interactiveShellInit = ''
        set -gx SOPS_AGE_KEY_FILE /home/philipp/.config/sops/age/keys.txt
      '';
    };

    home-manager.enable = true;
  };

  home.packages = [
    pkgs.nil
    pkgs.nixfmt
  ];
}
