# features/services/camofox/default.nix
{
  config,
  lib,
  ...
}:

let
  cfg = config.my.features.services.camofox;
in
{
  options.my.features.services.camofox = {
    enable = lib.mkEnableOption "Camofox anti-detection browser";
  };

  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers = {
      backend = "docker";
      containers.camofox = {
        image = "ghcr.io/jo-inc/camofox-browser:latest";
        autoStart = true;
        pull = "always";
        ports = [ "127.0.0.1:9377:9377" ];
        volumes = [ "/var/lib/camofox:/root/.camofox" ];
      };
    };
  };
}
