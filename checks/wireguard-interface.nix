{
  pkgs,
  lib,
  inputs,
}:
let
  mkSystem = (import ../lib/mk-system.nix { inherit (inputs) home-manager-unstable; }).mkSystem;
  system = "x86_64-linux";
  globalModules = [
    inputs.sops-nix.nixosModules.sops
    inputs.nod.nixosModules.default
  ];

  # The same builder the flake uses, but with the mesh interface renamed: if any consumer
  # spelled the name instead of reading the option, its output still says wg0 and this fails.
  fixture =
    (mkSystem {
      inherit system globalModules inputs;
      hostname = "hom-wrk-01";
      flake = null;
      extraModules = [
        { my.features.system.networking.wireguard.interfaceName = "wgtest0"; }
      ];
    }).config;

  rules = fixture.networking.firewall.extraInputRules;
  renamed = lib.hasInfix "wgtest0" rules && !(lib.hasInfix "wg0" rules);
  declared = fixture.networking.wireguard.interfaces ? wgtest0;
in
if renamed && declared then
  pkgs.runCommandLocal "wireguard-interface-check" { } ''
    echo "renamed mesh interface reaches the rendered firewall rules" > "$out"
  ''
else
  throw "wireguard interface fixture failed: renamed=${toString renamed} declared=${toString declared}"
