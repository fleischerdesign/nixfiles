{
  pkgs,
  self,
  lib,
  ...
}:
let
  manifest = name: self.nixosConfigurations.${name}.config.my.features.dev.openchamber.mesh.manifest;
  pc = manifest "hom-wrk-01";
  notebook = manifest "mob-nb-01";
  server = manifest "hom-srv-01";
  names = model: map (host: host.name) model.hosts;
  disabled =
    (self.nixosConfigurations.hom-wrk-01.extendModules {
      modules = [ { my.features.dev.openchamber.mesh.enable = lib.mkForce false; } ];
    }).config.my.features.dev.openchamber.mesh.manifest;
  completelyDisabled =
    (self.nixosConfigurations.hom-wrk-01.extendModules {
      modules = [ { my.features.dev.openchamber.enable = lib.mkForce false; } ];
    }).config.my.features.dev.openchamber.mesh.manifest;
  narrowed =
    (self.nixosConfigurations.hom-wrk-01.extendModules {
      modules = [ { my.features.dev.openchamber.mesh.targets = lib.mkForce [ "hom-srv-01" ]; } ];
    }).config.my.features.dev.openchamber.mesh.manifest;

in
assert
  names pc == [
    "hom-srv-01"
    "mob-nb-01"
  ];
assert
  names notebook == [
    "hom-srv-01"
    "hom-wrk-01"
  ];
assert names server == [ ];
assert pc.server.clients == [ "mob-nb-01" ];
assert notebook.server.clients == [ "hom-wrk-01" ];
assert
  server.server.clients == [
    "hom-wrk-01"
    "mob-nb-01"
  ];
assert disabled.hosts == [ ] && disabled.server.clients == [ ];
assert completelyDisabled.hosts == [ ] && completelyDisabled.server == null;
assert names narrowed == [ "hom-srv-01" ];
pkgs.runCommand "openchamber-mesh-check"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.nodejs_24
      pkgs.git
    ];
  }
  ''
    cp -R ${../features/dev/openchamber/lib} lib
    python3 lib/test_reconcile.py \
      ${pkgs.custom.openchamber-web}/lib/openchamber/node_modules/@openchamber/web/server/index.js \
      ${pkgs.nodejs_24}/bin/node
    cp ${../packages/custom/openchamber-desktop/managed-hosts.mjs} managed-hosts.mjs
    cp ${../packages/custom/openchamber-desktop/managed-hosts.test.mjs} managed-hosts.test.mjs
    cp ${../packages/custom/openchamber-desktop/managed-runtime.mjs} managed-runtime.mjs
    node --test managed-hosts.test.mjs
    touch $out
  ''
