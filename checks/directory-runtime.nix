{
  pkgs,
  lib,
  self,
  ...
}:
let
  hosts = lib.filterAttrs (
    _: host: host.config.my.features.services.authentik.server.enable
  ) self.nixosConfigurations;
  measure =
    name: host:
    let
      subjects = {
        user = "directory-fixture-owner";
        referenceUser = "directory-fixture-ui-reference";
        managed = "directory-fixture-managed";
        ordinary = "directory-fixture-ordinary";
      };
      config =
        (host.extendModules {
          modules = [
            {
              my.directory = {
                users.${subjects.user}.initialProfile = {
                  displayName = "Fixture owner";
                  email = "initial@example.test";
                };
                users.${subjects.referenceUser} = { };
                groups = {
                  ${subjects.managed}.members = [
                    subjects.user
                    subjects.referenceUser
                  ];
                  ${subjects.ordinary} = { };
                };
              };
            }
          ];
        }).config;
      expectations = pkgs.writeText "directory-runtime-expectations.json" (
        builtins.toJSON {
          inherit subjects;
          directory = config.my.directory;
          reportScript = lib.removePrefix "file:" config.systemd.services.authentik-directory-report.serviceConfig.StandardInput;
        }
      );
      verifier = lib.removePrefix "file:" config.systemd.services.authentik-blueprints-apply.serviceConfig.StandardInput;
    in
    {
      inherit name;
      path = pkgs.runCommand "directory-runtime-${name}" { nativeBuildInputs = [ pkgs.python3 ]; } ''
        set -euo pipefail
        python3 ${./directory-runtime.py} \
          ${host.pkgs.authentik}/bin/ak ${host.pkgs.postgresql_18}/bin \
          ${config.my.features.services.authentik.server.blueprintsDir} \
          ${verifier} ${expectations} ${./directory-runtime-measure.py} > "$out"
      '';
    };
in
pkgs.linkFarm "directory-runtime-check" (lib.mapAttrsToList measure hosts)
