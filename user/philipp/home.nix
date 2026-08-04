{
  pkgs,
  osConfig,
  inputs,
  ...
}:
{
  imports = [
    ./packages.nix
    ./opencode.nix
    ./fish.nix
    inputs.nixcord.homeModules.nixcord
  ];

  home.username = osConfig.my.user.name;
  home.homeDirectory = "/home/${osConfig.my.user.name}";
  home.stateVersion = "24.05";

  systemd.user.startServices = "sd-switch";

  xdg.desktopEntries."ls3d-handler" = {
    name = "WBS Learnspace 3D Handler";
    exec = "/home/${osConfig.my.user.name}/ls3d-handler.sh %u";
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

  my.features.desktop.webapps = {
    enable = true;
    apps = {
      moebius = {
        displayName = "Moebius";
        url = "https://moebius.rls.ancoris.ovh";
        icon = ../../media/moebius.png;
        comment = "Hermes Moebius Subdomain Gateway";
        categories = [
          "Network"
        ];
        wmClass = "moebius";
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
