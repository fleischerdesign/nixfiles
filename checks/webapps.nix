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
      ${pkgs.python3}/bin/python3 - "$@" <<'PY'
      import json, os, sys
      from pathlib import Path
      Path(os.environ["CALL_LOG"]).write_text(json.dumps(sys.argv[1:]))
      sys.exit(int(os.environ.get("BROWSER_EXIT", "0")))
      PY
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
  hosts = lib.mapAttrs (
    _: host:
    let
      user = host.config.home-manager.users.${host.config.my.user.primary};
    in
    {
      apps = user.my.features.desktop.webapps.apps;
      packages = map toString (
        builtins.filter (package: lib.hasPrefix "webapp-package-" package.name) user.home.packages
      );
      enabled = user.programs.firefox.policies.Preferences."browser.taskbarTabs.enabled";
      mime = user.xdg.mimeApps.defaultApplications;
      firefox = lib.getExe user.programs.firefox.finalPackage;
    }
  ) graphicalHosts;
  nativeFirefox =
    let
      host = graphicalHosts.${builtins.head (lib.attrNames graphicalHosts)}.config;
    in
    host.home-manager.users.${host.my.user.primary}.programs.firefox.finalPackage;
  manifest = pkgs.writeText "webapps-test.json" (
    builtins.toJSON {
      inherit hosts;
      arguments = firefoxArgs { url = "http://webapp.example.test"; };
      fixture = "${builtins.head inherited.config.home.packages}/bin/webapp-fixture";
      expected = (firefoxArgs { url = "https://webapp.example.test"; }) ++ [ "argument with spaces" ];
    }
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
      (pkgs.python3.withPackages (ps: [ ps.selenium ]))
      nativeFirefox
      pkgs.geckodriver
    ];
  }
  ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    export FONTCONFIG_FILE=${pkgs.makeFontsConf { fontDirectories = [ pkgs.dejavu_fonts ]; }}
    export MOZ_DISABLE_CONTENT_SANDBOX=1
    python3 ${./webapps.py} ${nativeFirefox}/lib/firefox/firefox ${pkgs.geckodriver}/bin/geckodriver ${manifest}
    touch "$out"
  ''
