# features/desktop/noctalia/home.nix - shell settings and the Niri adapter.
{
  config,
  lib,
  osConfig ? { },
  ...
}:
let
  cfg = config.my.features.desktop.noctalia;
  niriEnabled = osConfig.my.features.desktop.niri.enable or false;
  noctalia = lib.getExe config.programs.noctalia.package;
in
{
  options.my.features.desktop.noctalia = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = osConfig.my.features.desktop.noctalia.enable or false;
      defaultText = lib.literalExpression "osConfig.my.features.desktop.noctalia.enable";
      description = "Run Noctalia for this account.";
    };

    wallpaper = lib.mkOption {
      type = lib.types.nullOr (lib.types.either lib.types.path lib.types.str);
      default = null;
      description = "Initial wallpaper for this account; null leaves Noctalia's default.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        programs.noctalia = {
          enable = true;
          # The compositor starts the shell. Never start a second copy via systemd.
          systemd.enable = false;
          settings = {
            shell = {
              polkit_agent = true;
              setup_wizard_enabled = false;
            };
            theme.mode = "dark";
          }
          // lib.optionalAttrs (cfg.wallpaper != null) {
            wallpaper = {
              enabled = true;
              default.path = toString cfg.wallpaper;
            };
          };
        };
      }
      (lib.mkIf niriEnabled {
        programs.niri.settings = with config.lib.niri.actions; {
          spawn-at-startup = [ { argv = [ noctalia ]; } ];

          # These keys are the adapter between a compositor and its shell, not
          # general Niri navigation. Noctalia owns the lock and polkit prompt.
          binds = {
            "Mod+Space".action = spawn noctalia "msg" "panel-toggle" "launcher";
            "Super+Alt+L".action = spawn noctalia "msg" "session" "lock";
            "Mod+S".action = spawn noctalia "msg" "panel-toggle" "control-center";
            "XF86AudioRaiseVolume".action = spawn noctalia "msg" "volume-up";
            "XF86AudioLowerVolume".action = spawn noctalia "msg" "volume-down";
            "XF86AudioMute".action = spawn noctalia "msg" "volume-mute";
            "XF86MonBrightnessUp".action = spawn noctalia "msg" "brightness-up";
            "XF86MonBrightnessDown".action = spawn noctalia "msg" "brightness-down";
          };
        };
      })
    ]
  );
}
