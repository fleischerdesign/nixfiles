{ lib, pkgs, ... }:
let
  directivesDir = ./opencode/directives;
  directiveNames = lib.pipe (builtins.readDir directivesDir) [
    lib.attrNames
    (lib.filter (lib.hasSuffix ".md"))
    (lib.sort (a: b: a < b))
  ];
  # OpenCode combines configured instructions after the system prompt and AGENTS.md files.
  # The sources stay as individual Markdown files; Nix owns only the generated bundle and
  # the small configuration that points OpenCode at it.
  directives = pkgs.writeText "opencode-directives.md" (
    lib.concatMapStringsSep "\n\n" (
      name:
      let
        body = builtins.readFile (directivesDir + "/${name}");
      in
      "<!-- Source: ${name} -->\n${body}"
    ) directiveNames
  );
in
{
  xdg.configFile."opencode/opencode.json".text = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
    instructions = [ "${directives}" ];
  };
}
