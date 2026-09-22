# user/philipp/profiles/core.nix
# Baseline CLI tools and utilities common to all environments (servers, workstations, notebooks).
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    attic-client
    antigravity-cli
    yazi
  ];
}
