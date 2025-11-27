# features/containers.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.containers;
in
{
  options.my.features.containers = {
    enable = lib.mkEnableOption "Containerization tools (Docker)";

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of system users to add to the 'docker' group.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Enable Docker daemon
    virtualisation.docker.enable = true;

    # Add specified users to the docker group
    users.extraGroups.docker.members = cfg.users;
  };
}
