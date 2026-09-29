{
  config,
  pkgs,
  osConfig,
  inputs,
  lib,
  ...
}:
{
  imports = [
    ./packages.nix
    ./opencode.nix
    ./openchamber.nix
    ./fish.nix
    inputs.nixcord.homeModules.nixcord
  ];

  # Username and home come from Home Manager's own per-user wiring (users.users.<name>),
  # not from the fleet's primary user: a second account must land in its own home.
  home.stateVersion = "24.05";

  systemd.user.startServices = "sd-switch";

  xdg.desktopEntries."ls3d-handler" = {
    name = "WBS Learnspace 3D Handler";
    exec = "${config.home.homeDirectory}/ls3d-handler.sh %u";
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

    home-manager.enable = true;
  };

  my.features.dev.git.enable = true;

  # GNOME personal choices. `enable` is inherited from the host's desktop feature, so this block is
  # inert on hosts that do not run GNOME.
  my.features.desktop.gnome = {
    background = ../../media/wallpaper.jpg;
    showBatteryPercentage = true;
    favoriteApps = [
      "org.gnome.Nautilus.desktop"
      "codium.desktop"
      "spotify.desktop"
      "obsidian.desktop"
      "google-chrome.desktop"
      "com.mitchellh.ghostty.desktop"
    ];
  };

  # GNOME Shell extensions, through Home Manager's single list: it installs each package and
  # enables the UUID derived from it. On hosts that do not run GNOME the list is inert.
  programs.gnome-shell.extensions = lib.optionals osConfig.my.features.desktop.gnome.enable [
    { package = pkgs.gnomeExtensions.tiling-shell; }
    { package = pkgs.gnomeExtensions.gsconnect; }
    { package = pkgs.gnomeExtensions.vitals; }
    { package = pkgs.gnomeExtensions.blur-my-shell; }
    { package = pkgs.gnomeExtensions.dash-to-dock; }
  ];

  # Dash to Dock and its blur integration, as the user had them before the desktop was rebuilt.
  dconf.settings = lib.optionalAttrs osConfig.my.features.desktop.gnome.enable {
    "org/gnome/shell/extensions/dash-to-dock" = {
      apply-custom-theme = true;
      intellihide-mode = "ALL_WINDOWS";
    };
    "org/gnome/shell/extensions/blur-my-shell/dash-to-dock" = {
      blur = true;
    };
  };

  my.features.desktop.noctalia.wallpaper = ../../media/wallpaper.jpg;

  # Personal Noctalia defaults. GUI changes in settings.toml may still override these.
  programs.noctalia.settings = lib.mkIf osConfig.my.features.desktop.noctalia.enable {
    theme = {
      source = "wallpaper";
      pure_black_dark = true;
    };
    shell = {
      avatar_path = "${../../media/avatar-philipp.jpg}";
      panel = {
        control_center_placement = "attached";
        open_near_click_control_center = true;
      };
    };
    location = {
      auto_locate = false;
      address = "Hufelandstraße 55, 17036 Neubrandenburg, Deutschland";
    };
  };

  my.features.desktop.webapps = {
    enable = true;
    apps = {
      ai = {
        displayName = "AI Assistant";
        url = "https://ai.${osConfig.my.topology.domain}";
        icon = ../../media/openclaw.png;
        comment = "AI Assistant (Open-WebUI)";
        categories = [
          "Network"
        ];
        wmClass = "open-webui";
      };

      gmail = {
        displayName = "Mail";
        url = "https://mail.google.com";
        icon = ../../media/gmail.png;
        comment = "Google Mail Web App";
        categories = [
          "Network"
          "Email"
        ];
        wmClass = "gmail";
      };

      calendar = {
        displayName = "Kalender";
        url = "https://calendar.google.com";
        icon = ../../media/google-calendar.png;
        comment = "Google Calendar Web App";
        categories = [
          "Utility"
          "Calendar"
        ];
        wmClass = "google-calendar";
      };

      tasks = {
        displayName = "Tasks";
        url = "https://tasks.google.com";
        icon = ../../media/google-tasks.png;
        comment = "Google Tasks Web App";
        categories = [
          "Utility"
        ];
        wmClass = "google-tasks";
      };

      photos = {
        displayName = "Fotos";
        url = "https://photos.google.com";
        icon = ../../media/google-photos.png;
        comment = "Google Photos Web App";
        categories = [
          "Graphics"
          "Photography"
        ];
        wmClass = "google-photos";
      };

      meet = {
        displayName = "Meet";
        url = "https://meet.google.com";
        icon = ../../media/google-meet.png;
        comment = "Google Meet Web App";
        categories = [
          "Network"
          "VideoConference"
        ];
        wmClass = "google-meet";
      };

      youtube = {
        displayName = "YouTube";
        url = "https://youtube.com";
        icon = ../../media/youtube.png;
        comment = "YouTube Web App";
        categories = [
          "AudioVideo"
          "Video"
        ];
        wmClass = "youtube";
      };
    };
  };

  home.packages = [
    pkgs.nil
    pkgs.nixfmt
  ];
}
