# A consumer that spells the interface name instead of reading the option works on the host where it
# was written and breaks on every host that renames it. The fixture renames the interface and fails
# if any consumer's output still says the old name.
{
  pkgs,
  lib,
  inputs,
  ...
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
  # The fixture reads the real fleet (flake = self); only its own interface name differs.
  fixture =
    (mkSystem {
      inherit system globalModules inputs;
      hostname = "hom-wrk-01";
      flake = inputs.self;
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
