{
  pkgs,
  lib,
  self,
  ...
}:
let
  fakeChrome = pkgs.writeShellApplication {
    name = "google-chrome-stable";
    text = ''
      printf '%s\n' "$@" > "$CALL_LOG"
      exit "''${BROWSER_EXIT:-0}"
    '';
  };
  fixture =
    browser: isolated:
    lib.evalModules {
      specialArgs = {
        pkgs = pkgs // {
          google-chrome = fakeChrome;
        };
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
          };
          config.my.features.desktop.webapps = {
            enable = true;
            defaultBrowser = browser;
            apps.fixture = {
              displayName = "Test webapp";
              url = "https://webapp.example.test/path";
              inherit isolated;
              extraArgs = [ "argument with spaces" ];
            };
          };
        }
      ];
    };
  inherited = fixture "chrome" false;
  isolated = fixture "chrome" true;
  rejected = fixture "epiphany" true;
  overridden = inherited.extendModules {
    modules = [ { my.features.desktop.webapps.apps.fixture.browser = "brave"; } ];
  };
  invalidName = inherited.extendModules {
    modules = [
      {
        my.features.desktop.webapps.apps."invalid name".displayName = "Invalid";
        my.features.desktop.webapps.apps."invalid name".url = "https://example.test";
      }
    ];
  };
  graphicalHosts = lib.filterAttrs (
    _: host: host.config.my.role != "server"
  ) self.nixosConfigurations;
  checkHost =
    name: host:
    let
      user = host.config.home-manager.users.${host.config.my.user.primary};
      apps = user.my.features.desktop.webapps.apps;
      packages = builtins.filter (
        package: lib.hasPrefix "webapp-package-" package.name
      ) user.home.packages;
    in
    assert !user.programs.firefox.enable;
    assert !(lib.elem "noctalia/bitwarden" user.my.features.desktop.noctalia.settings.plugins.enabled);
    assert lib.all (mime: user.xdg.mimeApps.defaultApplications.${mime} == [ "google-chrome.desktop" ])
      [
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
        expectedExec = "exec ${lib.escapeShellArg "${pkgs.google-chrome}/bin/google-chrome-stable"} ${
          lib.escapeShellArgs (
            [
              "--app=${app.url}"
              "--class=${app.wmClass}"
              "--name=${app.wmClass}"
            ]
            ++ app.extraArgs
          )
        }";
      in
      assert app.browser == "chrome";
      ''
        test -x ${package}/bin/webapp-${appName}
        grep -Fq -- ${lib.escapeShellArg expectedExec} ${package}/bin/webapp-${appName}
        grep -Fxq -- "Exec=$(readlink -f ${package}/bin/webapp-${appName})" ${package}/share/applications/webapp-${appName}.desktop
      ''
    ) packages
    + ''
      echo '${name}: ${toString (builtins.length packages)} Chrome launchers and MIME defaults checked'
    '';
  expected = pkgs.writeText "webapp-expected-arguments" (
    lib.concatStringsSep "\n" [
      "--app=https://webapp.example.test/path"
      "--class=fixture"
      "--name=fixture"
      "argument with spaces"
    ]
    + "\n"
  );
in
assert inherited.config.my.features.desktop.webapps.apps.fixture.browser == "chrome";
assert overridden.config.my.features.desktop.webapps.apps.fixture.browser == "brave";
assert lib.all (claim: claim.assertion) inherited.config.assertions;
assert lib.all (claim: claim.assertion) isolated.config.assertions;
assert !(lib.all (claim: claim.assertion) rejected.config.assertions);
assert !(lib.all (claim: claim.assertion) invalidName.config.assertions);
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
    export BROWSER_EXIT=0
    ${builtins.head isolated.config.home.packages}/bin/webapp-fixture
    cat ${expected} > isolated-expected
    printf '%s\n' "--user-data-dir=$HOME/.config/webapps/fixture" >> isolated-expected
    diff -u isolated-expected "$CALL_LOG"
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList checkHost graphicalHosts)}
    touch "$out"
  ''
