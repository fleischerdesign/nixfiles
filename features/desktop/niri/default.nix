# features/niri.nix
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.features.desktop.niri;
in
{
  options.my.features.desktop.niri = {
    enable = lib.mkEnableOption "Niri desktop environment";
  };

  config = lib.mkIf cfg.enable {
    # Dependencies
    my.features.system.wayland.enable = true;
    my.features.system.audio.enable = true;

    # Conflicts
    assertions = [
      {
        assertion = !config.my.features.desktop.gnome.enable;
        message = "Niri cannot be enabled alongside Gnome.";
      }
    ];

    # System-level configuration for Niri

    # Disable X server for a pure Wayland setup
    services = {
      xserver.enable = false;
      gvfs.enable = true;
      greetd = {
        enable = true;
        settings = {
          default_session = {
            command = "${pkgs.niri}/bin/niri-session";
            user = "philipp";
          };
        };
      };
      upower.enable = true;
      power-profiles-daemon.enable = true;
      gnome.gnome-keyring.enable = true;
      locate = {
        enable = true;
        package = pkgs.plocate;
      };
    };

    programs.niri.enable = true;
    programs.niri.package = pkgs.niri;

    xdg.portal = {
      enable = true;
      config.common.default = [ "gnome" ];
      extraPortals = [
        pkgs.xdg-desktop-portal-gtk
        pkgs.xdg-desktop-portal-gnome
      ];
    };

    # Home Manager-level configuration for Niri
    home-manager.sharedModules = [
      (
        {
          inputs,
          pkgs,
          config,
          lib,
          hostname,
          ...
        }:
        {
          home.packages = [
            inputs.axis.packages.${pkgs.stdenv.hostPlatform.system}.default
            pkgs.adwaita-icon-theme
            pkgs.brightnessctl
            pkgs.libnotify
            pkgs.sushi
            pkgs.polkit_gnome
          ];

          programs.niri.settings = with config.lib.niri.actions; {
            cursor = {
              theme = "Adwaita";
              size = 24;
            };

            prefer-no-csd = true;

            xwayland-satellite.enable = true;
            xwayland-satellite.path = lib.getExe pkgs.xwayland-satellite;

            window-rules = [
              {
                matches = [ ];
                focus-ring.active.color = "#364A2B";
                geometry-corner-radius = {
                  top-left = 10.0;
                  top-right = 10.0;
                  bottom-left = 10.0;
                  bottom-right = 10.0;
                };
                clip-to-geometry = true;
              }
              {
                matches = [ { title = "^Bild im Bild$"; } ];
                open-floating = true;
                open-focused = false;
                default-column-width.fixed = 480;
                default-window-height.fixed = 270;
                default-floating-position = {
                  relative-to = "bottom-right";
                  x = 20;
                  y = 20;
                };
              }
            ];

            spawn-at-startup = [
              # Start Polkit Agent
              {
                argv = [
                  "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
                ];
              }
              {
                argv = [
                  "axis-shell"
                  "--wallpaper"
                  "/etc/nixos/media/wallpaper.jpg"
                  "--locked"
                ];
              }
            ];

            outputs = lib.mkIf (hostname == "jello") {
              "DP-1" = {
                position = {
                  x = 320;
                  y = 0;
                };
              };
              "HDMI-A-2" = {
                position = {
                  x = 0;
                  y = 1080;
                };
                focus-at-startup = true;
              };
            };

            binds = {
              "Mod+Return".action = spawn "ghostty";
              "Mod+Space".action =
                spawn-sh "busctl --user call org.axis.Shell /org/axis/Shell org.axis.Shell ToggleLauncher";

              "Mod+Shift+Slash".action = show-hotkey-overlay;
              "Super+Alt+L".action =
                spawn-sh "busctl --user call org.axis.Shell /org/axis/Shell org.axis.Shell Lock";

              "XF86AudioRaiseVolume".action = spawn-sh "wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 0.1+";
              "XF86AudioLowerVolume".action = spawn-sh "wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.1-";
              "XF86AudioMute".action = spawn-sh "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
              "XF86AudioMicMute".action = spawn-sh "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";

              "XF86MonBrightnessUp".action = spawn-sh "brightnessctl set 15%+";
              "XF86MonBrightnessDown".action = spawn-sh "brightnessctl set 15%-";
              "Mod+Q".action = close-window;

              "Mod+Left".action = focus-column-left;
              "Mod+Right".action = focus-column-right;
              "Mod+Down".action = focus-window-down;
              "Mod+Up".action = focus-window-up;
              "Mod+H".action = focus-column-left;
              "Mod+L".action = focus-column-right;
              "Mod+K".action = focus-window-up;
              "Mod+J".action = focus-window-down;

              "Mod+Ctrl+Left".action = move-column-left;
              "Mod+Ctrl+Right".action = move-column-right;
              "Mod+Ctrl+Up".action = move-window-up;
              "Mod+Ctrl+Down".action = move-window-down;
              "Mod+Ctrl+H".action = move-column-left;
              "Mod+Ctrl+L".action = move-column-right;
              "Mod+Ctrl+K".action = move-window-up;
              "Mod+Ctrl+J".action = move-window-down;

              "Mod+Home".action = focus-column-first;
              "Mod+End".action = focus-column-last;
              "Mod+Ctrl+Home".action = move-column-to-first;
              "Mod+Ctrl+End".action = move-column-to-last;

              "Mod+Comma".action = consume-window-into-column;
              "Mod+Period".action = expel-window-from-column;

              "Mod+Shift+Left".action = focus-monitor-left;
              "Mod+Shift+Right".action = focus-monitor-right;
              "Mod+Shift+Down".action = focus-monitor-down;
              "Mod+Shift+Up".action = focus-monitor-up;
              "Mod+Shift+H".action = focus-monitor-left;
              "Mod+Shift+L".action = focus-monitor-right;
              "Mod+Shift+K".action = focus-monitor-up;
              "Mod+Shift+J".action = focus-monitor-down;

              "Mod+Shift+Ctrl+Left".action = move-column-to-monitor-left;
              "Mod+Shift+Ctrl+Right".action = move-column-to-monitor-right;
              "Mod+Shift+Ctrl+Up".action = move-column-to-monitor-up;
              "Mod+Shift+Ctrl+Down".action = move-column-to-monitor-down;
              "Mod+Shift+Ctrl+H".action = move-column-to-monitor-left;
              "Mod+Shift+Ctrl+L".action = move-column-to-monitor-right;
              "Mod+Shift+Ctrl+K".action = move-column-to-monitor-up;
              "Mod+Shift+Ctrl+J".action = move-column-to-monitor-down;

              "Mod+Page_Down".action = focus-workspace-down;
              "Mod+Page_Up".action = focus-workspace-up;
              "Mod+U".action = focus-workspace-down;
              "Mod+I".action = focus-workspace-up;

              "Mod+Ctrl+Page_Down".action = move-column-to-workspace-down;
              "Mod+Ctrl+Page_Up".action = move-column-to-workspace-up;
              "Mod+Ctrl+U".action = move-column-to-workspace-down;
              "Mod+Ctrl+I".action = move-column-to-workspace-up;

              "Mod+Shift+Page_Down".action = move-workspace-down;
              "Mod+Shift+Page_Up".action = move-workspace-up;
              "Mod+Shift+U".action = move-workspace-down;
              "Mod+Shift+I".action = move-workspace-up;

              "Mod+1".action = focus-workspace 1;
              "Mod+2".action = focus-workspace 2;
              "Mod+3".action = focus-workspace 3;
              "Mod+4".action = focus-workspace 4;
              "Mod+5".action = focus-workspace 5;
              "Mod+6".action = focus-workspace 6;
              "Mod+7".action = focus-workspace 7;
              "Mod+8".action = focus-workspace 8;
              "Mod+9".action = focus-workspace 9;

              "Mod+R".action = switch-preset-column-width;
              "Mod+Shift+R".action = switch-preset-window-height;
              "Mod+Ctrl+R".action = reset-window-height;

              "Mod+F".action = maximize-column;
              "Mod+Shift+F".action = fullscreen-window;

              "Mod+C".action = center-column;

              "Mod+Minus".action = set-column-width "-10%";
              "Mod+Adiaeresis".action = set-column-width "+10%";
              "Mod+Shift+Minus".action = set-window-height "-10%";
              "Mod+Shift+Adiaeresis".action = set-window-height "+10%";

              "Mod+V".action = toggle-window-floating;
              "Mod+Shift+V".action = switch-focus-between-floating-and-tiling;

              "Mod+Shift+P".action = power-off-monitors;
              "Mod+Shift+E".action = quit;
            };
          };
        }
      )
    ];
  };
}
