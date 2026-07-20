# lib/features.nix
# Declarative feature dependency utilities for the my.features module system.
{
  lib,
}:

let
  /*
    Build a nested attrset from a dot-separated path.
    e.g. "services.postgresql" → { services = { postgresql = {}; }; }
  */
  mkNested =
    value: parts:
    let
      head = builtins.head parts;
      tail = builtins.tail parts;
    in
    if tail == [ ] then { ${head} = value; } else { ${head} = mkNested value tail; };

  /*
    Auto-enable dependent features with lib.mkDefault.
    Also asserts that dependencies are enabled — build fails if host
    explicitly disabled one that a feature requires.
  */
  requireOne =
    dep: config:
    let
      parts = lib.splitString "." dep;
      enablePath = [
        "my"
        "features"
      ]
      ++ parts
      ++ [ "enable" ];
    in
    {
      my.features = mkNested { enable = lib.mkDefault true; } parts;
      assertions = [
        {
          assertion = lib.getAttrFromPath enablePath config;
          message = "my.features.${dep}.enable must be true (required by this feature)";
        }
      ];
    };

  requires = deps: config: lib.mkMerge (map (dep: requireOne dep config) deps);
in
{
  inherit requires;
}
