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
        ExecStart = "${mnemosynePkgs.hermes}/bin/mnemosyne-hermes --hermes-home /var/lib/hermes/.hermes install --force";
      };
    };
  };
}
