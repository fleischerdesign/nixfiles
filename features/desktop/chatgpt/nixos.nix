{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.my.features.desktop.chatgpt.enable =
    lib.mkEnableOption "Official ChatGPT desktop for Home Manager users";
  config = {
    assertions = lib.optionals config.my.features.desktop.chatgpt.enable [
      {
        assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
        message = "ChatGPT desktop is packaged for x86_64-linux.";
      }
      {
        assertion = config.my.features.system.wayland.enable;
        message = "ChatGPT desktop requires a Wayland session.";
      }
    ];
    home-manager.sharedModules = [ ./home.nix ];
  };
}
