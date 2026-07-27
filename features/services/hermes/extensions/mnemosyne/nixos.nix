# features/services/hermes/extensions/mnemosyne/nixos.nix — Mnemosyne extension
#
# Provides the Mnemosyne memory provider for hermes-agent. Mnemosyne
# stores conversation memory as vector embeddings in a SQLite database
# (sqlite-vec extension). The bootstrap oneshot service initializes
# the database before the agent starts.
#
# The extension contributes its Python packages (memory + hermes CLI)
# through the core module's extraPythonPackages injection point.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  hcfg = config.my.features.services.hermes;
  ecfg = config.my.features.services.hermes.extensions.mnemosyne;
  mnemosynePkgs = pkgs.callPackage ./package.nix { };
in
{
  options.my.features.services.hermes.extensions.mnemosyne = {
    enable = lib.mkEnableOption "Mnemosyne memory extension";
  };

  config = lib.mkIf (hcfg.enable && ecfg.enable) {
    systemd.services.hermes-agent-mnemosyne-bootstrap = {
      description = "Bootstrap Mnemosyne memory provider";
      wantedBy = [ "hermes-agent.service" ];
      before = [ "hermes-agent.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "hermes";
        Group = "hermes";
        ExecStart = "${mnemosynePkgs.hermes}/bin/mnemosyne-hermes --hermes-home ${hcfg.stateDir}/.hermes install --force";
      };
    };
  };
}
