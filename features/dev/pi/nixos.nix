{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.my.features.dev.pi;
  system = pkgs.stdenv.hostPlatform.system;
  # The upstream flake builds Pi from source and restores the model catalog at build time, so it
  # tracks `main` between nixpkgs releases. Freshness is why this feature takes the flake; the
  # package option keeps the choice overridable per host, for a pinned revision or a rollback.
  defaultPackage = inputs.pi.packages.${system}.default;
in
{
  options.my.features.dev.pi = {
    enable = lib.mkEnableOption "the Pi coding agent";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      defaultText = lib.literalExpression "inputs.pi.packages.${pkgs.stdenv.hostPlatform.system}.default";
      description = "Pi package, from the upstream flake by default.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    # Extensions are read from the agent directory, which is a home path: the account scope owns
    # the symlinks while the system scope owns the binary.
    home-manager.sharedModules = [ ./home.nix ];
  };
}
