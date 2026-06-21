# roles/server.nix
# This role defines the default features for a headless server.
{...}: {
  imports = [
    ./base.nix
  ];

  my.role = "server";
}
