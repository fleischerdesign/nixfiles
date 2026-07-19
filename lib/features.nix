# lib/features.nix
# Declarative feature dependency utilities for the my.features module system.
{
  lib,
}:

let
  /*
    Auto-enable dependent features with lib.mkDefault.
    Also asserts that dependencies are enabled — build fails if host
    explicitly disabled one that a feature requires.

    Usage:
      config = lib.mkIf cfg.enable (lib.mkMerge [
        { ... }
        (features.requires [ "services.postgresql" "services.redis" ] config)
      ]);
  */
  requires = deps: config: lib.mkMerge (map (dep: requireOne dep config) deps);

  requireOne =
    dep: config:
    let
      parts = lib.splitString "." dep;
      depPath = [
        "my"
        "features"
      ]
      ++ parts;
      enablePath = depPath ++ [ "enable" ];
    in
    lib.mkMerge [
      # Soft: auto-enable with lowest priority — host can override
      (lib.setAttrByPath enablePath (lib.mkDefault true) { })
      # Hard: build error if host explicitly disabled the dependency
      {
        assertions = [
          {
            assertion = lib.getAttrFromPath enablePath config;
            message = "my.features.${dep}.enable must be true (required by this feature)";
          }
        ];
      }
    ];
in
{
  inherit requires;
}
