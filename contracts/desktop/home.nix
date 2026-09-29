# contracts/desktop/home.nix - the account-scope half of the desktop domain.
#
# A compositor's shell draws surfaces and a user runs applications; both want a background
# effect, and the compositor that renders it owns the vocabulary for it. The schema below
# therefore states intent only: which surface or window wants an effect, whether it blurs
# its own background or wants one, and what that effect samples. Niri's `xray`, `passes`
# and `offset` names live in `features/desktop/niri`, which projects every entry into one
# compositor rule. A second compositor reads the same entries unchanged.
#
# This half is attached by the domain's own `nixos.nix` through `home-manager.sharedModules`,
# the same mechanism a feature uses for its `home.nix`. No second module marker and no change
# to discovery or system composition is involved.
{ lib, config, ... }:
let
  fraction = lib.types.addCheck lib.types.float (value: value >= 0.0 && value <= 1.0);

  entry = lib.types.submodule {
    options = {
      kind = lib.mkOption {
        type = lib.types.enum [
          "window"
          "layer"
        ];
        description = "Whether the entry selects an application window or a shell layer surface.";
      };

      ids = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Window app-id patterns; only for kind = \"window\".";
      };

      titles = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Window title patterns; only for kind = \"window\".";
      };

      namespaces = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Layer namespace patterns; only for kind = \"layer\".";
      };

      blur = lib.mkOption {
        type = lib.types.enum [
          "auto"
          "on"
          "off"
        ];
        default = "auto";
        description = ''
          `auto` emits nothing and lets the surface ask for the effect itself through the
          background-effect protocol, which keeps its own shape and settings. `on` blurs
          even for a surface that asks for nothing; `off` takes blur away from one that asks.
        '';
      };

      sample = lib.mkOption {
        type = lib.types.enum [
          "behind"
          "backdrop"
        ];
        default = "behind";
        description = ''
          What the effect samples: `behind` takes what is really under the surface, so
          stacking a window over it changes the result; `backdrop` takes the wallpaper
          alone, which is cheaper and stays steady while a window animates.
        '';
      };

      opacity = lib.mkOption {
        type = lib.types.nullOr fraction;
        default = null;
        description = ''
          Transparency of the selected surface. An effect is invisible without it: an opaque
          window covers whatever was sampled. Null leaves the surface as it is.
        '';
      };

      popups = lib.mkOption {
        type = lib.types.submodule {
          options = {
            enable = lib.mkEnableOption "a background effect on this surface's pop-ups";
            opacity = lib.mkOption {
              type = lib.types.nullOr fraction;
              default = null;
              description = "Transparency for the pop-ups, on top of the surface's own.";
            };
          };
        };
        default = { };
        description = "Menus and tooltips of the selected surface.";
      };
    };
  };
in
{
  options.my.desktop.effects = lib.mkOption {
    type = lib.types.attrsOf entry;
    default = { };
    description = ''
      Background effects a shell or a user requests, keyed by name. The compositor's
      projection decides how each entry reaches its rules; nothing here names a compositor.
    '';
  };

  config = {
    assertions = [
      {
        assertion = builtins.all (
          effect:
          builtins.length effect.ids + builtins.length effect.titles + builtins.length effect.namespaces > 0
        ) (lib.attrValues config.my.desktop.effects);
        message = "desktop: every background effect needs at least one selector";
      }
      {
        assertion = builtins.all (
          effect:
          (effect.kind != "window" || effect.namespaces == [ ])
          && (effect.kind != "layer" || (effect.ids == [ ] && effect.titles == [ ]))
        ) (lib.attrValues config.my.desktop.effects);
        message = ''
          desktop: window selectors (ids/titles) belong to kind = "window" and namespaces
          to kind = "layer", but an entry mixes them
        '';
      }
    ];
  };
}
