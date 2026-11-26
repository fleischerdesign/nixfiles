{ lib, pkgs, ... }:
let
  # Content-addressed copies keep a change elsewhere in the repository from moving these store
  # paths; only the files themselves decide them. OpenCode combines configured instructions after
  # the system prompt and AGENTS.md files, so the sources stay individual Markdown files and Nix
  # owns only the generated bundle.
  directivesDir = builtins.path {
    path = ./opencode/directives;
    name = "opencode-directives";
  };
  directiveNames = lib.pipe (builtins.readDir directivesDir) [
    lib.attrNames
    (lib.filter (lib.hasSuffix ".md"))
    (lib.sort (a: b: a < b))
  ];
  directives = pkgs.writeText "opencode-directives.md" (
    lib.concatMapStringsSep "\n\n" (
      name:
      let
        body = builtins.readFile (directivesDir + "/${name}");
      in
      "<!-- Source: ${name} -->\n${body}"
    ) directiveNames
  );

  # Agents are discovered the same way: one Markdown file per agent, installed under the global
  # configuration. Adding an agent is adding a file, with no manifest to keep in sync.
  agentsDir = builtins.path {
    path = ./opencode/agents;
    name = "opencode-agents";
  };
  agentNames = lib.pipe (builtins.readDir agentsDir) [
    lib.attrNames
    (lib.filter (lib.hasSuffix ".md"))
    (lib.sort (a: b: a < b))
  ];
  agents = builtins.listToAttrs (
    map (name: {
      name = "opencode/agents/${name}";
      value.source = agentsDir + "/${name}";
    }) agentNames
  );
in
{
  xdg.configFile = agents // {
    "opencode/opencode.json".text = builtins.toJSON {
      "$schema" = "https://opencode.ai/config.json";
      instructions = [ "${directives}" ];
    };
  };
}
