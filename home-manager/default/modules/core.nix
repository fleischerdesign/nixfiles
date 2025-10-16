{ pkgs, ... }:

{
  programs = {
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    fish = {
      enable = true;
      shellAliases = {
        c = "codium";
      };
    };
  };

  # Basic packages that every user should have
  home.packages = [
    pkgs.nil
    pkgs.nixfmt-rfc-style
  ];
}
