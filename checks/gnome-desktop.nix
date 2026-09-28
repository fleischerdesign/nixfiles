# checks/gnome-desktop.nix - the GNOME desktop feature, asserted where its consumers see it.
#
# The subject is one evaluated host plus the user's Home Manager configuration, because that is
# where the dconf database and the session actually come from. Every positive assertion has a
# negative control beside it: the shared exclusivity rule is exercised on a focused fixture, the
# personal/user split is exercised by forcing the personal options empty, and the extension
# mechanism is exercised by adding one extension and observing that the generated settings change.
{
  pkgs,
  lib,
  self,
  ...
}:
let
  host = self.nixosConfigurations.hom-wrk-01;
  cfg = host.config;
  philipp = cfg.home-manager.users.philipp;

  # `dconf.settings` values are GVariant: arrays arrive wrapped as `{ type; value = [ ... ]; }`,
  # while booleans and strings are merged as plain Nix values.
  settings = philipp.dconf.settings;
  gvalue = value: if builtins.isAttrs value && value ? value then value.value else value;
  shellSettings = settings."org/gnome/shell" or { };
  interfaceSettings = settings."org/gnome/desktop/interface" or { };
  backgroundSettings = settings."org/gnome/desktop/background" or { };
  inputSettings = settings."org/gnome/desktop/input-sources" or { };
  favoriteIds = map gvalue (gvalue (shellSettings."favorite-apps" or [ ]));

  # Control 1 - the one-session invariant, exercised through the contract's own interface, so the
  # test cannot drift from the features it guards and needs no feature option stubbed.
  assertionsOption = {
    options.assertions = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [ ];
    };
  };
  evalEnvironments =
    environments:
    (lib.evalModules {
      modules = [
        assertionsOption
        ../contracts/desktop/nixos.nix
        { my.desktop.environments = environments; }
      ];
    }).config;
  failedExclusivity = evalEnvironments {
    gnome = true;
    niri = true;
  };
  exclusivityViolation = lib.any (
    assertion: !assertion.assertion && lib.hasInfix "one desktop environment" assertion.message
  ) failedExclusivity.assertions;
  singleDesktopClean =
    !(lib.any (assertion: !assertion.assertion) (evalEnvironments { gnome = true; }).assertions);

  # Control 2 - the personal/user split: with the personal list forced empty, the shared module must
  # not have written a favourite list behind the user's back.
  withoutFavorites =
    (host.extendModules {
      modules = [
        { home-manager.users.philipp.my.features.desktop.gnome.favoriteApps = lib.mkForce [ ]; }
      ];
    }).config.home-manager.users.philipp.dconf.settings;
  sharedKeepsNoFavorites = !(withoutFavorites."org/gnome/shell" or { } ? "favorite-apps");

  # Control 3 - the extension mechanism: Home Manager's one list installs the package and enables
  # its UUID, and the "no extensions" default then no longer applies.
  fixtureExtension =
    (pkgs.runCommand "gnome-extension-fixture" { } ''
      mkdir -p "$out/share/gnome-shell/extensions/fixture@example.invalid"
    '')
    // {
      extensionUuid = "fixture@example.invalid";
    };
  withExtension =
    (host.extendModules {
      modules = [
        {
          home-manager.users.philipp.programs.gnome-shell.extensions = [
            { package = fixtureExtension; }
          ];
        }
      ];
    }).config.home-manager.users.philipp.dconf.settings."org/gnome/shell";
  enabledExtensionIds = map gvalue (gvalue (withExtension."enabled-extensions" or [ ]));
in
if
  # The session, its display manager and the absence of the previous one.
  cfg.services.desktopManager.gnome.enable
  && cfg.services.displayManager.gdm.enable
  && cfg.services.displayManager.defaultSession == "gnome"
  && !cfg.services.greetd.enable
  && !cfg.my.features.desktop.niri.enable
  # The site's app exclusions reach the option GNOME reads.
  && cfg.environment.gnome.excludePackages == cfg.my.features.desktop.gnome.excludePackages
  # The shipped default is classic GNOME: no extensions, dark scheme, German layout, wallpaper set.
  && philipp.programs.gnome-shell.enable
  && philipp.programs.gnome-shell.extensions == [ ]
  && shellSettings."disable-user-extensions" == true
  && builtins.length (gvalue shellSettings."enabled-extensions") == 0
  && interfaceSettings."color-scheme" == "prefer-dark"
  && builtins.length (gvalue inputSettings.sources) == 1
  && builtins.elem "org.gnome.Nautilus.desktop" favoriteIds
  && lib.hasInfix "wallpaper.jpg" backgroundSettings."picture-uri"
  # Negative controls.
  && exclusivityViolation
  && singleDesktopClean
  && sharedKeepsNoFavorites
  && withExtension."disable-user-extensions" == false
  && builtins.elem "fixture@example.invalid" enabledExtensionIds
  # The dormant Axis module stays unimported: it applies its configuration without an enable
  # guard, which is how wl-clipboard, mDNS publishing and TCP 7391 reached hosts that do not run
  # Axis at all. Both the source and the effect are guarded.
  && !(lib.hasInfix "axis.nixosModules" (builtins.readFile ../features/desktop/niri/nixos.nix))
  && !(builtins.elem 7391 cfg.networking.firewall.allowedTCPPorts)
then
  pkgs.runCommandLocal "gnome-desktop-check" { } ''
    echo "GNOME session/GDM, desktop exclusivity, user split and extension mechanism passed" > "$out"
  ''
else
  throw "gnome desktop check failed: session, exclusions, user settings or extension controls did not hold"
