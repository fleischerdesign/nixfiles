# user/hermes/home.nix — Hermes agent user Home Manager module
#
# Minimal home-manager config: deploys shared OpenCode settings,
# git, and gh for the hermes user. Skipped on hosts where the
# Hermes agent service is active (rollins) — there the hermes
# feature module handles deployment via systemd.tmpfiles.
{
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  hermesEnabled = osConfig.my.features.services.hermes.enable or false;
  ocfg = osConfig.my.features.dev.opencode or { };
  opencodeEnabled = ocfg.enable or false;
in
{
  home.username = "hermes";
  home.homeDirectory = osConfig.users.users.hermes.home;
  home.stateVersion = "24.11";

  home.packages = with pkgs; [
    opencode
    nodejs
    antigravity-cli
  ];

  home.file = lib.mkIf (!hermesEnabled && opencodeEnabled) {
    ".config/opencode/opencode.json".source = toString ocfg.configJsonPath;
  };
}
