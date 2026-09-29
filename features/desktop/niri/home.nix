# features/desktop/niri/home.nix - the per-user half of the Niri feature.
#
# This is also the projection of `my.desktop.effects`: the domain schema states intent, this
# file owns the compositor's vocabulary and turns each entry into exactly one rule. Niri is
# free to name things its way (`xray`, `passes`) without any of it leaking into the schema.
{
  pkgs,
  config,
  inputs,
  lib,
  osConfig ? { },
  ...
}:
let
  # The output layout is a system-side declaration; the user side reads it.
  sys = osConfig.my.features.desktop.niri;

  kdl = inputs.niri.lib.kdl;
  blur = config.my.features.desktop.niri.blur;

  # A frosted surface's pop-ups use the same one transparency value as everything else.
  surfaceOpacity = config.my.desktop.surfaceOpacity;

  # `auto` leaves blur to the surface's own request; only `on` or `off` speak for it.
  backgroundEffect =
    effect:
    kdl.plain "background-effect" (
      lib.optional (effect.blur == "on") (kdl.leaf "blur" true)
      ++ lib.optional (effect.blur == "off") (kdl.leaf "blur" false)
      ++ [ (kdl.leaf "xray" (effect.sample == "backdrop")) ]
    );

  # Niri makes a pop-up translucent itself, because the application draws it opaque, so a
  # frosted pop-up loses some content opacity; that is why it is only written when the session
  # is frosted at all.
  popups =
    effect:
    lib.optional (effect.popups && surfaceOpacity < 1.0) (
      kdl.plain "popups" [
        (kdl.leaf "opacity" surfaceOpacity)
        (kdl.plain "background-effect" [
          (kdl.leaf "blur" true)
          (kdl.leaf "xray" false)
        ])
      ]
    );

  # A window that asks for a background effect gets its border drawn as an outline: a border
  # filled with background would cover exactly the effect the window asked for.
  rule =
    effect:
    let
      matches =
        map (id: kdl.leaf "match" { app-id = id; }) effect.ids
        ++ map (title: kdl.leaf "match" { title = title; }) effect.titles
        ++ map (namespace: kdl.leaf "match" { namespace = namespace; }) effect.namespaces;
    in
    kdl.plain (if effect.kind == "window" then "window-rule" else "layer-rule") (
      matches
      ++ lib.optional (effect.kind == "window" && effect.blur != "off") (
        kdl.leaf "draw-border-with-background" false
      )
      ++ [ (backgroundEffect effect) ]
      ++ popups effect
    );

  # Niri's own defaults hold until a value is set, so this node exists only then.
  blurNode =
    lib.optional
      (
        !blur.enable
        || lib.any (value: value != null) [
          blur.passes
          blur.offset
          blur.noise
          blur.saturation
        ]
      )
      (
        kdl.plain "blur" (
          lib.optional (!blur.enable) (kdl.flag "off")
          ++ lib.optional (blur.passes != null) (kdl.leaf "passes" blur.passes)
          ++ lib.optional (blur.offset != null) (kdl.leaf "offset" blur.offset)
          ++ lib.optional (blur.noise != null) (kdl.leaf "noise" blur.noise)
          ++ lib.optional (blur.saturation != null) (kdl.leaf "saturation" blur.saturation)
        )
      );

  effectNodes = blurNode ++ map rule (lib.attrValues config.my.desktop.effects);
in
{
  options.my.features.desktop.niri.blur = lib.mkOption {
    type = lib.types.submodule {
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether background blur exists at all; false disables it for the whole session.";
        };
        passes = lib.mkOption {
          type = lib.types.nullOr lib.types.ints.positive;
          default = null;
          description = "Dual kawase passes: more is a larger blur at more GPU cost.";
        };
        offset = lib.mkOption {
          type = lib.types.nullOr lib.types.float;
          default = null;
          description = "Per-pass offset multiplier; larger is smoother at no GPU cost, until it artifacts.";
        };
        noise = lib.mkOption {
          type = lib.types.nullOr lib.types.float;
          default = null;
          description = "Pixel noise over the blur, which reduces colour banding.";
        };
        saturation = lib.mkOption {
          type = lib.types.nullOr lib.types.float;
          default = null;
          description = "Saturation of the blurred background; 1 is unchanged.";
        };
      };
    };
    default = { };
    description = ''
      Niri's blur quality, applied to every background effect. A value left null is not
      written at all, so Niri's own default holds instead of being pinned here.
    '';
  };

  config = {
    home.packages = [
      pkgs.adwaita-icon-theme
      pkgs.sushi
    ];

    programs.niri.settings = with config.lib.niri.actions; {
      input.keyboard.xkb.layout = "de";

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
          geometry-corner-radius = {
            top-left = 20.0;
            top-right = 20.0;
            bottom-left = 20.0;
            bottom-right = 20.0;
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

      inherit (sys) outputs;

      binds = {
        "Mod+Return".action = spawn "ghostty";
        "Mod+Shift+Slash".action = show-hotkey-overlay;

        "XF86AudioMicMute".action = spawn-sh "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";

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

    # Extend Niri's generated KDL; never replace the rest of the configuration.
    programs.niri.config = lib.mkOptionDefault effectNodes;
  };
}
