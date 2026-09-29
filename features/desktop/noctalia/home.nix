# features/desktop/noctalia/home.nix - the shell's own settings and its Niri adapter.
#
# The shell owns every seam to an application: see ./integrations/. Each integration
# names the template it selects together with the configuration that makes the
# application consume it, so an application feature never mentions the shell. What
# stays here is the shell itself and the compositor it runs inside.
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

  # Built-in templates whose seam is the template itself: Noctalia writes the theme file
  # *and* the application's own selection, and no Home Manager-owned file is involved.
  # `niri` is one of them because its seam is the include in the adapter below.
  unseamedBuiltinIds = [
    "btop"
    "kcolorscheme"
    "niri"
  ];
in
{
  imports = [
    ./integrations/community-templates.nix
    ./integrations/ghostty.nix
    ./integrations/gtk.nix
    ./integrations/nvim.nix
    ./integrations/obsidian.nix
    ./integrations/qt.nix
    ./integrations/vscode.nix
  ];

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
            theme = {
              mode = "dark";
              templates = {
                enable_builtin_templates = true;
                enable_community_templates = true;
                builtin_ids = unseamedBuiltinIds;
              };
            };
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
            # The file is created by Noctalia after Niri starts. Keep the include
            # optional and absolute: the main config is a Nix-store symlink.
            (leaf "include" [
              { optional = true; }
              "${config.xdg.configHome}/niri/noctalia.kdl"
            ])
          ]
        );

        programs.niri.settings = with config.lib.niri.actions; {
          spawn-at-startup = [ { argv = [ noctalia ]; } ];

          # The session environment is owned here because Niri starts the session.
          environment.QT_QPA_PLATFORMTHEME = "qt6ct";

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
