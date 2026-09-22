# user/philipp/packages.nix
# Profile-based package aggregator using algebraic composition.
# Imports declared profiles (e.g. core, graphical) without host-leak branching.
{
  osConfig,
  ...
}:
let
  userProfiles = osConfig.my.user.profiles or [ "core" ];
in
{
  imports = map (profileName: ./profiles + "/${profileName}.nix") userProfiles;
}
