{
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  role = osConfig.my.role;
  opencodeDir = ../../features/dev/opencode;
in
{
  programs.opencode = lib.mkIf (role != "server") {
    enable = true;
    extraPackages = [ pkgs.nodejs ];
    settings = {
      instructions = [
        "~/.config/opencode/instructions/engineering-constitution.md"
      ];
      mcp = {
        nixos = {
          type = "local";
          command = [ (lib.getExe pkgs.mcp-nixos) ];
          enabled = true;
        };
        chrome-devtools = {
          type = "local";
          command = [
            "npx"
            "-y"
            "chrome-devtools-mcp@latest"
            "--executablePath"
            (lib.getExe pkgs.google-chrome)
          ];
          enabled = true;
        };
      };
      plugin = [
        "context-mode"
        "opencode-pty"
        "opencode-direnv"
      ];
    };
  };

  home.file = lib.mkIf (role != "server") (
    # Engineering Constitution (instructions file)
    {
      ".config/opencode/instructions/engineering-constitution.md".source =
        opencodeDir + "/instructions/engineering-constitution.md";
    }
    # Skills
    // {
      ".config/opencode/skills/architecture-design/SKILL.md".source =
        opencodeDir + "/skills/architecture-design/SKILL.md";
      ".config/opencode/skills/code-review/SKILL.md".source =
        opencodeDir + "/skills/code-review/SKILL.md";
      ".config/opencode/skills/spec-first/SKILL.md".source =
        opencodeDir + "/skills/spec-first/SKILL.md";
      ".config/opencode/skills/systematic-debugging/SKILL.md".source =
        opencodeDir + "/skills/systematic-debugging/SKILL.md";
      ".config/opencode/skills/systematic-exploration/SKILL.md".source =
        opencodeDir + "/skills/systematic-exploration/SKILL.md";
      ".config/opencode/skills/systematic-refactoring/SKILL.md".source =
        opencodeDir + "/skills/systematic-refactoring/SKILL.md";
      ".config/opencode/skills/tdd-discipline/SKILL.md".source =
        opencodeDir + "/skills/tdd-discipline/SKILL.md";
    }
    # Agents
    // {
      ".config/opencode/agents/implement/AGENT.md".source =
        opencodeDir + "/agents/implement/AGENT.md";
      ".config/opencode/agents/review/AGENT.md".source =
        opencodeDir + "/agents/review/AGENT.md";
    }
  );
}
