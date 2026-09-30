{
  pkgs,
  lib,
  self,
  ...
}:
let
  firefoxArgs = import ../features/desktop/webapps/firefox-args.nix;
  fakeFirefox = pkgs.writeShellApplication {
    name = "firefox";
    text = ''
      printf '%s\n' "$@" > "$CALL_LOG"
      exit "''${BROWSER_EXIT:-0}"
    '';
  };
  fixture =
    browser: isolated:
    lib.evalModules {
      specialArgs = {
        inherit pkgs;
        osConfig.my.role = "desktop";
      };
      modules = [
        ../features/desktop/webapps/home.nix
        {
          options = {
            assertions = lib.mkOption {
              type = lib.types.listOf lib.types.attrs;
              default = [ ];
            };
            home.packages = lib.mkOption { type = lib.types.listOf lib.types.package; };
            programs.firefox = {
              enable = lib.mkOption { type = lib.types.bool; };
              package = lib.mkOption { type = lib.types.package; };
              finalPackage = lib.mkOption { type = lib.types.package; };
              policies = lib.mkOption {
                type = lib.types.attrs;
                default = { };
              };
            };
          };
          config = {
            programs.firefox = {
              enable = true;
              package = fakeFirefox;
              finalPackage = fakeFirefox;
            };
            my.features.desktop.webapps = {
              enable = true;
              defaultBrowser = browser;
              apps.fixture = {
                displayName = "Test webapp";
                url = "https://webapp.example.test";
                inherit isolated;
                extraArgs = [ "argument with spaces" ];
              };
            };
          };
        }
      ];
    };
  inherited = fixture "firefox" false;
  rejected = fixture "firefox" true;
  overridden = inherited.extendModules {
    modules = [ { my.features.desktop.webapps.apps.fixture.browser = "chrome"; } ];
  };
  invalidUrl = inherited.extendModules {
    modules = [
      { my.features.desktop.webapps.apps.fixture.url = lib.mkForce "https://webapp.example.test/path"; }
    ];
  };
  missingBrowser = inherited.extendModules {
    modules = [ { programs.firefox.enable = lib.mkForce false; } ];
  };
  # Only build webapp packages, not the rest of a user's desktop closure.
  graphicalHosts = lib.filterAttrs (_: cfg: cfg.config.my.role != "server") self.nixosConfigurations;
  checkHost =
    name: host:
    let
      user = host.config.home-manager.users.${host.config.my.user.primary};
      apps = user.my.features.desktop.webapps.apps;
      packages = builtins.filter (
        package: lib.hasPrefix "webapp-package-" package.name
      ) user.home.packages;
      firefox = lib.getExe user.programs.firefox.finalPackage;
    in
    assert
      user.programs.firefox.policies.Preferences."browser.taskbarTabs.enabled" == {
        Value = true;
        Status = "locked";
      };
    assert lib.all (mime: user.xdg.mimeApps.defaultApplications.${mime} == [ "firefox.desktop" ]) [
      "text/html"
      "x-scheme-handler/http"
      "x-scheme-handler/https"
    ];
    assert builtins.length packages == builtins.length (lib.attrNames apps);
    lib.concatMapStringsSep "\n" (
      package:
      let
        appName = lib.removePrefix "webapp-package-" package.name;
        app = apps.${appName};
        arguments =
          (firefoxArgs {
            inherit (app) url;
            container = app.firefoxContainer;
          })
          ++ app.extraArgs;
        expectedExec = "exec ${lib.escapeShellArg firefox} ${lib.escapeShellArgs arguments}";
      in
      assert app.browser == "firefox";
      ''
        # Inspect the built artifact, including the policy-wrapped browser path.
        test -x ${package}/bin/webapp-${appName}
          grep -Fq -- ${lib.escapeShellArg expectedExec} ${package}/bin/webapp-${appName}
          grep -Fxq -- "Exec=$(readlink -f ${package}/bin/webapp-${appName})" ${package}/share/applications/webapp-${appName}.desktop
      ''
    ) packages
    + ''
      echo '${name}: ${toString (builtins.length packages)} Firefox launchers and MIME defaults checked'
    '';
  expected = pkgs.writeText "webapp-expected-arguments" (
    lib.concatStringsSep "\n" (
      (firefoxArgs { url = "https://webapp.example.test"; }) ++ [ "argument with spaces" ]
    )
    + "\n"
  );
in
assert inherited.config.my.features.desktop.webapps.apps.fixture.browser == "firefox";
assert overridden.config.my.features.desktop.webapps.apps.fixture.browser == "chrome";
assert (fixture "chrome" false).config.my.features.desktop.webapps.apps.fixture.browser == "chrome";
assert lib.all (claim: claim.assertion) inherited.config.assertions;
assert !(lib.all (claim: claim.assertion) rejected.config.assertions);
assert !(lib.all (claim: claim.assertion) invalidUrl.config.assertions);
assert !(lib.all (claim: claim.assertion) missingBrowser.config.assertions);
pkgs.runCommandLocal "webapps-check"
  {
    nativeBuildInputs = [
      pkgs.diffutils
      pkgs.gnugrep
    ];
  }
  ''
    export CALL_LOG="$TMPDIR/arguments"
    for expected_status in 0 17; do
      export BROWSER_EXIT="$expected_status"
      if ${builtins.head inherited.config.home.packages}/bin/webapp-fixture; then
        actual_status=0
      else
        actual_status=$?
      fi
      test "$actual_status" -eq "$expected_status"
      diff -u ${expected} "$CALL_LOG"
    done
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList checkHost graphicalHosts)}
    touch "$out"
  ''
