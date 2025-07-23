{ pkgs, ... }:

{
  programs.nixvim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
  };
}
