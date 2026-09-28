# checks/gnome-desktop.nix - the GNOME desktop feature, asserted where its consumers see it.
#
# The file draws a hard line between two kinds of statement:
#
#   * system invariants are read from the real host: which session runs, which display manager owns
#     it, that the previous desktop is off, which apps are excluded, and that the dormant Axis
#     module neither is imported nor opens a port;
#   * module behaviour is read from fixtures whose values this check sets itself. Nothing here
#     asserts a personal preference of the primary user - adding or removing a favourite, a
#     wallpaper or an extension must never require touching this file.
#
# The one exception is deliberate and self-adjusting: the extension compatibility loop reads the
# user's real extension list and checks each package's own metadata against the pinned GNOME Shell
# release, so it grows with the list instead of needing edits.
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
  # while booleans and strings merge as plain Nix values.
  gvalue = value: if builtins.isAttrs value && value ? value then value.value else value;
  ids = value: map gvalue (gvalue value);
  shellOf = user: user.dconf.settings."org/gnome/shell" or { };
  interfaceOf = user: user.dconf.settings."org/gnome/desktop/interface" or { };
  backgroundOf = user: user.dconf.settings."org/gnome/desktop/background" or { };

  # A fixture extension only needs the two things the module reads: the package (for home.packages)
  # and its UUID (from which Home Manager derives the enabled id).
  fixtureExtension =
    name: uuid:
    (pkgs.runCommand name { } ''
      mkdir -p "$out/share/gnome-shell/extensions/${uuid}"
      printf '%s' '{"uuid":"${uuid}","shell-version":["50"],"name":"${name}"}' \
        > "$out/share/gnome-shell/extensions/${uuid}/metadata.json"
    '')
    // {
      extensionUuid = uuid;
    };

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

  # Controls 2 and 3 - the per-user module, evaluated on values the check states, never on the
  # values the primary user happens to hold.
  personalValues =
    overrides:
    {
      enable = true;
      background = null;
      favoriteApps = [ ];
      colorScheme = "prefer-dark";
      showBatteryPercentage = false;
      inputSources = [
        [
          "xkb"
          "de"
        ]
      ];
    }
    // overrides;

  fixture =
    {
      personal ? { },
      extensions ? [ ],
    }:
    (host.extendModules {
      modules = [
        {
          home-manager.users.philipp.my.features.desktop.gnome = lib.mkForce (personalValues personal);
          home-manager.users.philipp.programs.gnome-shell.extensions = lib.mkForce extensions;
        }
      ];
    }).config.home-manager.users.philipp;

  plain = fixture { };
  configured = fixture {
    personal = {
      background = ../media/wallpaper.jpg;
      favoriteApps = [ "example.desktop" ];
      showBatteryPercentage = true;
    };
  };
  withExtensions = fixture {
    extensions = [
      { package = fixtureExtension "gnome-extension-a" "fixture-a@example.invalid"; }
      { package = fixtureExtension "gnome-extension-b" "fixture-b@example.invalid"; }
    ];
  };
  fixtureExtensionIds = ids (shellOf withExtensions)."enabled-extensions";

  # The user's real list, read only to verify compatibility against the pinned shell release. This
  # loop adapts to the list; it never asserts which extensions are in it.
  enabledExtensions = map (extension: {
    inherit (extension) id;
    package = "${extension.package}";
  }) philipp.programs.gnome-shell.extensions;
  extensionsJson = builtins.toJSON enabledExtensions;
  shellRelease = lib.versions.major pkgs.gnome-shell.version;
in
if
  # System invariants on the real host.
  cfg.services.desktopManager.gnome.enable
  && cfg.services.displayManager.gdm.enable
  && cfg.services.displayManager.defaultSession == "gnome"
  && !cfg.services.greetd.enable
  && !cfg.my.features.desktop.niri.enable
  && cfg.my.desktop.environments.gnome
  && cfg.environment.gnome.excludePackages == cfg.my.features.desktop.gnome.excludePackages
  # The dormant Axis module stays unimported and its port stays closed: it applied its
  # configuration with no enable guard, which is how wl-clipboard, mDNS publishing and TCP 7391
  # reached hosts that do not run Axis at all.
  && !(lib.hasInfix "axis.nixosModules" (builtins.readFile ../features/desktop/niri/nixos.nix))
  && !(builtins.elem 7391 cfg.networking.firewall.allowedTCPPorts)
  # The per-user module is actually wired for the real account (the value is the user's business).
  && philipp.programs.gnome-shell.enable
  && philipp.dconf.settings ? "org/gnome/desktop/interface"
  # Module behaviour, on stated values: with no extensions the "off" switch is written...
  && (shellOf plain)."disable-user-extensions" == true
  && builtins.length (ids (shellOf plain)."enabled-extensions") == 0
  # ...and no personal key appears when its value is the neutral one.
  && !((shellOf plain) ? "favorite-apps")
  && !(plain.dconf.settings ? "org/gnome/desktop/background")
  && !((interfaceOf plain) ? "show-battery-percentage")
  && (interfaceOf plain)."color-scheme" == "prefer-dark"
  && builtins.length (gvalue (plain.dconf.settings."org/gnome/desktop/input-sources").sources) == 1
  # Stated personal values do produce their keys.
  && builtins.elem "example.desktop" (ids (shellOf configured)."favorite-apps")
  && (interfaceOf configured)."show-battery-percentage" == true
  && lib.hasInfix "wallpaper.jpg" (backgroundOf configured)."picture-uri"
  # With a non-empty list the "off" switch yields to Home Manager, which installs and enables
  # exactly the packages given.
  && (shellOf withExtensions)."disable-user-extensions" == false
  &&
    fixtureExtensionIds == [
      "fixture-a@example.invalid"
      "fixture-b@example.invalid"
    ]
  && lib.any (
    package: (package.extensionUuid or "") == "fixture-a@example.invalid"
  ) withExtensions.home.packages
  && lib.any (
    package: (package.extensionUuid or "") == "fixture-b@example.invalid"
  ) withExtensions.home.packages
  # Exclusivity controls.
  && exclusivityViolation
  && singleDesktopClean
then
  pkgs.runCommandLocal "gnome-desktop-check"
    {
      nativeBuildInputs = [ pkgs.jq ];
      inherit extensionsJson shellRelease;
    }
    ''
      # Every extension the user enables must declare support for the pinned GNOME Shell release.
      # The list is read from the configuration, so adding an extension is checked automatically
      # instead of silently loading nothing.
      fail=0
      count=$(jq 'length' <<< "$extensionsJson")
      index=0
      while [ "$index" -lt "$count" ]; do
        id=$(jq -r ".[$index].id" <<< "$extensionsJson")
        package=$(jq -r ".[$index].package" <<< "$extensionsJson")
        metadata="$package/share/gnome-shell/extensions/$id/metadata.json"
        if [ ! -f "$metadata" ]; then
          echo "gnome-desktop: $id ships no metadata.json at $metadata" >&2
          fail=1
        elif ! jq -e --arg release "$shellRelease" '."shell-version" | index($release)' "$metadata" > /dev/null; then
          echo "gnome-desktop: $id does not declare support for GNOME Shell $shellRelease: $(jq -c '."shell-version"' "$metadata")" >&2
          fail=1
        fi
        index=$((index + 1))
      done
      if [ "$fail" -ne 0 ]; then
        exit 1
      fi
      echo "GNOME session/GDM, session invariant, module behaviour on stated values, extension mechanism and extension compatibility passed" > "$out"
    ''
else
  throw "gnome desktop check failed: a system invariant, a module behaviour on stated values, or an exclusivity control did not hold"
