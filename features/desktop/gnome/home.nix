# features/desktop/gnome/home.nix - the per-user half of the GNOME feature.
#
# It carries only the GNOME defaults this site considers structural (colour scheme, German layout)
# and options for everything personal. Favourites, wallpaper and battery indicator are declared by
# the user, not baked in here, so a second account cannot inherit the first one's choices and the
# shared module stays free of host or person facts.
#
# GNOME Shell extensions are deliberately *not* declared here: Home Manager already owns that
# mechanism in `programs.gnome-shell.extensions`, one list that both installs the package and
# enables its UUID. This file only makes the empty case explicit - classic GNOME, user extensions
# off - so "no extensions" is a stated default rather than a side effect.
{
  config,
  lib,
  osConfig ? { },
  ...
}:
let
  cfg = config.my.features.desktop.gnome;

  # The system side owns the switch; a user inherits it and may still opt out per account.
  inherited = osConfig.my.features.desktop.gnome.enable or false;

  # GSettings wants `a(ss)`: an array of (type, id) tuples. Nix lists alone would be an `as`.
  asSources = sources: map (source: lib.hm.gvariant.mkTuple source) sources;
in
{
  options.my.features.desktop.gnome = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = inherited;
      defaultText = lib.literalExpression "osConfig.my.features.desktop.gnome.enable";
      description = "Write GNOME settings for this account.";
    };

    background = lib.mkOption {
      type = lib.types.nullOr (lib.types.either lib.types.path lib.types.str);
      default = null;
      example = lib.literalExpression "../../media/wallpaper.jpg";
      description = "Desktop and lock-screen wallpaper; null keeps GNOME's default.";
    };

    favoriteApps = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Desktop entries pinned to the dash; empty keeps GNOME's own default set.";
    };

    colorScheme = lib.mkOption {
      type = lib.types.enum [
        "default"
        "prefer-dark"
        "prefer-light"
      ];
      default = "prefer-dark";
      description = "GNOME colour scheme (`org.gnome.desktop.interface.color-scheme`).";
    };

    showBatteryPercentage = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Show the battery percentage in the status area.";
    };

    inputSources = lib.mkOption {
      type = lib.types.listOf (lib.types.listOf lib.types.str);
      default = [
        [
          "xkb"
          "de"
        ]
      ];
      example = lib.literalExpression ''
        [
          [ "xkb" "de" ]
          [ "xkb" "us" ]
        ]
      '';
      description = ''
        Keyboard layouts as `[ type id ]` pairs for `org.gnome.desktop.input-sources.sources`;
        the first entry is the active layout. GNOME on Wayland reads its layout here, not from
        `services.xserver.xkb`, so this is what makes a German keyboard work in the session.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Home Manager's single extension list; enabling the module makes it available to the user.
    programs.gnome-shell.enable = true;

    dconf.settings = {
      "org/gnome/desktop/interface" = {
        color-scheme = cfg.colorScheme;
      }
      // lib.optionalAttrs cfg.showBatteryPercentage {
        show-battery-percentage = true;
      };

      "org/gnome/desktop/input-sources" = {
        sources = asSources cfg.inputSources;
        mru-sources = asSources cfg.inputSources;
      };

      # `favorite-apps` is only written when the user declared one, and the extension switch only
      # when Home Manager's list is empty: with extensions, upstream owns both keys.
      "org/gnome/shell" =
        lib.optionalAttrs (cfg.favoriteApps != [ ]) { favorite-apps = cfg.favoriteApps; }
        // lib.optionalAttrs (config.programs.gnome-shell.extensions == [ ]) {
          disable-user-extensions = true;
          enabled-extensions = [ ];
        };
    }
    // lib.optionalAttrs (cfg.background != null) {
      "org/gnome/desktop/background" = {
        picture-uri = "file://${cfg.background}";
        picture-uri-dark = "file://${cfg.background}";
      };
    };
  };
}
