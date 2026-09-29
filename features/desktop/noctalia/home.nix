# features/desktop/noctalia/home.nix - shell settings and the Niri adapter.
{
  config,
  inputs,
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
            # The Noctalia backdrop is shown in Niri's overview by the layer rule below.
            backdrop.enabled = niriEnabled;
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
        # niri-flake's typed settings do not yet expose Niri 26.04's
        # background-effect rules. Extend its generated KDL rather than
        # replacing the rest of the compositor configuration.
        programs.niri.config = lib.mkOptionDefault (
          with inputs.niri.lib.kdl;
          [
            (plain "layer-rule" [
              (leaf "match" { namespace = "^noctalia-(bar-[^\"]+|notification|dock|panel|attached-panel|osd)$"; })
              (plain "background-effect" [ (leaf "xray" false) ])
            ])
            (plain "layer-rule" [
              (leaf "match" { namespace = "^noctalia-window-switcher$"; })
              (plain "background-effect" [
                (leaf "blur" true)
                (leaf "xray" false)
              ])
            ])
          ]
        );

        programs.niri.settings = with config.lib.niri.actions; {
          spawn-at-startup = [ { argv = [ noctalia ]; } ];

          # Allow Noctalia's notification actions to focus their target windows.
          debug.honor-xdg-activation-with-invalid-serial = [ ];

          window-rules = [
            {
              matches = [ { app-id = "^dev\\.noctalia\\.Noctalia$"; } ];
              open-floating = true;
              default-column-width.fixed = 1080;
              default-window-height.fixed = 920;
            }
          ];

          layer-rules = [
            {
              matches = [ { namespace = "^noctalia-backdrop"; } ];
              place-within-backdrop = true;
            }
          ];

          # These keys are the adapter between a compositor and its shell, not
          # general Niri navigation. Noctalia owns the lock and polkit prompt.
          binds = {
            "Mod+Space".action = spawn noctalia "msg" "panel-toggle" "launcher";
            "Super+Alt+L".action = spawn noctalia "msg" "session" "lock";
            "Mod+S".action = spawn noctalia "msg" "panel-toggle" "control-center";
            "Mod+Shift+Comma".action = spawn noctalia "msg" "settings-toggle";
            "Alt+Tab".action = spawn noctalia "msg" "window-switcher";
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
