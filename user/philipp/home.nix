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
  # Which templates are selected and how each application consumes them is owned by the
  # Noctalia feature (`features/desktop/noctalia`), not by a user file.
  my.features.desktop.noctalia.settings = lib.mkIf osConfig.my.features.desktop.noctalia.enable {
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

    # The bar: navigation, then time and media, then state (system, then applications),
    # then attention, then action. `wallpaper` is dropped because the wallpaper is declared
    # in this repository; the launcher is dropped because it is reached with Mod+Space.
    bar.default = {
      position = "top";
      widget_spacing = 10;
      start = [ "workspaces" ];
      center = [
        "media"
        "clock"
      ];
      end = [
        "tray"
        "network"
        "bluetooth"
        "volume"
        "brightness"
        "battery"
        "icefish/phone-operate:status"
        "andrewdems/printers:printer"
        "privacy"
        "notifications"
        "clipboard"
        "control-center"
        "session"
      ];
    };

    # The bar shows only what is happening: idle indicators and empty states stay out.
    widget = {
      clock.anchor = true;
      privacy.hide_inactive = true;
      bluetooth.hide_when_no_connected_device = true;
      notifications.hide_when_no_unread = true;
      media.hide_when_no_media = true;
    };

    # Power profiles are not worth a slot on a desktop; the microphone mute is a real
    # toggle the bar does not cover. Home Assistant's entities are chosen in the shell, not
    # declared here, because which entity is meant is a personal decision.
    control_center.shortcuts = [
      { type = "wifi"; }
      { type = "bluetooth"; }
      { type = "caffeine"; }
      { type = "nightlight"; }
      { type = "notification"; }
      { type = "mic_mute"; }
    ];

    # A session without a greeter passes no password to PAM, so the login keyring
    # is locked at boot and the first client that wants a secret would raise its
    # own unlock dialog. Starting the shell locked means the one password the lock
    # screen already takes unlocks the session and the keyring together, because
    # its PAM stack includes pam_gnome_keyring.
    hooks.started = "${lib.getExe config.programs.noctalia.package} msg session lock";
  };

  # One transparency value for every frosted surface; bar, panels, OSD, dock and the
  # terminal all read it, so they cannot drift apart.
  my.desktop.surfaceOpacity = 0.85;

  # Personal taste belongs in the registry: the compositor blurs behind every window, and
  # only the ones that paint a translucent background (Ghostty, and GTK applications through
  # the shell's frost stylesheet) actually show it. The pop-ups are frosted with the same
  # transparency value, so no second number appears anywhere.
  my.desktop.effects = lib.mkIf osConfig.my.features.desktop.niri.enable {
    frosted-windows = {
      kind = "window";
      ids = [ "^.*$" ];
      blur = "on";
      popups = true;
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
