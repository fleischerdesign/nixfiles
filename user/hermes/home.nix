# user/hermes/home.nix — Hermes agent user Home Manager module
{
  pkgs,
  osConfig,
  ...
}:
{
  home.username = "hermes";
  home.homeDirectory = osConfig.users.users.hermes.home;
  home.stateVersion = "24.11";

  home.packages = with pkgs; [
    nodejs
    antigravity-cli
  ];

  my.features.dev.opencode.enable = true;
  my.features.dev.git.enable = true;
}
