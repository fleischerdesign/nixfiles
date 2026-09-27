# features/desktop/webapps/nixos.nix — Declarative PWA / WebApp launcher generator module
{ lib, ... }:
{
  options.my.features.desktop.webapps = {
    enable = lib.mkEnableOption "Declarative PWA / WebApp launcher feature module";
  };

  config = {
    # The per-user half is home.nix; the schema lives there because the app definitions are user
    # configuration, and the system side stays the switch that registers it.
    home-manager.sharedModules = [ ./home.nix ];
  };
}
