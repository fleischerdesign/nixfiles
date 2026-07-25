# extensions/pi-subagents/default.nix
{ config, lib, ... }:
let
  cfg = config.my.features.dev.pi.extensions.pi-subagents;
  piLib = {
    inherit (import ../../lib/extension-files.nix { inherit lib; }) filesModule;
    inherit (import ../../lib/extra-settings.nix { inherit lib; }) scalarExtraSettings mkCheckShadowing;
  };
  extPath = "my.features.dev.pi.extensions.pi-subagents";
  knownKeys = [
    "maxConcurrent" "defaultMaxTurns" "graceTurns" "defaultJoinMode"
    "schedulingEnabled" "scopeModels" "widgetMode"
  ];

  # ── Agent frontmatter validation ───────────────────────────────────────
  #
  # YAML frontmatter in agent .md files must be well-formed.  The most
  # common failure mode is an unquoted value containing ": " (colon-space)
  # which YAML parses as a nested mapping inside a compact mapping.
  #
  # This assertion catches that specific pattern at eval time — no external
  # parser dependency, pure Nix.

  agentsDir = ./agents;
  agentNames = builtins.filter (n: n != null) (
    builtins.map (n: if builtins.match ".*\\.md" n != null then n else null)
      (builtins.attrNames (builtins.readDir agentsDir))
  );

  # Extract frontmatter (text between first two "---" markers)
  extractFM =
    content:
    let
      stripped = builtins.match "---\n(.*)\n---.*" content;
    in
    if stripped == null then "" else builtins.elemAt stripped 0;

  # True when line is a YAML key-value with an unquoted colon in the value.
  # Pattern:  key: value: rest
  # The first ": " is the mapping separator; any subsequent ": " is a syntax error.
  hasNestedColon =
    line:
    let
      matches = builtins.match "[^:]+: [^\"].*: .*" line;
    in
    matches != null;

  # For each agent, check every frontmatter line
  agentChecks =
    builtins.map (name:
      let
        content = builtins.readFile (agentsDir + "/${name}");
        fm = extractFM content;
        lines = builtins.filter (l: l != "") (lib.splitString "\n" fm);
        bad = builtins.filter hasNestedColon lines;
      in
      {
        inherit name bad;
      }
    ) agentNames;
in
{
  options.my.features.dev.pi.extensions.pi-subagents = {
    enable = lib.mkEnableOption "pi-subagents";
    package = lib.mkOption {
      type = lib.types.str;
      default = "npm:@tintinweb/pi-subagents";
      description = "NPM package specifier for this extension.";
    };
    maxConcurrent = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4;
    };
    defaultMaxTurns = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 0;
    };
    graceTurns = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 3;
    };
    defaultJoinMode = lib.mkOption {
      type = lib.types.enum [ "smart" "group" "individual" ];
      default = "smart";
    };
    schedulingEnabled = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    scopeModels = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
    widgetMode = lib.mkOption {
      type = lib.types.enum [ "all" "background" "off" ];
      default = "background";
    };
    extraSettings = lib.mkOption ({ default = { }; } // piLib.scalarExtraSettings);

    _files = lib.mkOption {
      type = piLib.filesModule;
      default = { };
      description = "Files to deploy (set by extension, read by orchestrator).";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions =
      piLib.mkCheckShadowing extPath knownKeys config
      ++ (lib.concatMap (check:
        lib.optionals (check.bad != []) [
          {
            assertion = false;
            message = ''
              Invalid YAML frontmatter in agent "${check.name}":
              ${builtins.concatStringsSep "\n  " check.bad}

              Values containing ": " (colon-space) must be quoted in YAML.
              Example fix:  description: "search breadth: \"quick\" for ..."
            '';
          }
        ]
      ) agentChecks);

    my.features.dev.pi.extensions.pi-subagents._files = {
      config.".pi/agent/subagents.json" =
        {
          maxConcurrent = cfg.maxConcurrent;
          defaultMaxTurns = cfg.defaultMaxTurns;
          graceTurns = cfg.graceTurns;
          defaultJoinMode = cfg.defaultJoinMode;
          schedulingEnabled = cfg.schedulingEnabled;
          scopeModels = cfg.scopeModels;
          widgetMode = cfg.widgetMode;
        }
        // cfg.extraSettings;

      assets.".pi/agent/agents" = ./agents;
    };
  };
}
