{config, pkgs, ...}:
{
    home.sessionVariables = {
    EDITOR = "codium";
  };

  programs.vscode = {
    enable = true;
    package = pkgs.vscodium;
    mutableExtensionsDir = false;
    extensions = with pkgs.vscode-extensions; [
      continue.continue
      jnoortheen.nix-ide
      prisma.prisma
      ms-python.python
      vue.volar
      mkhl.direnv
      ms-vscode.cpptools
      ms-vscode.makefile-tools
      jnoortheen.nix-ide
    ];
    userSettings = {
      "git.confirmSync" = false;
      "git.autofetch" = true;
      "terminal.integrated.fontWeight" = "normal";

      "window.titleBarStyle" = "custom";
      "window.customTitleBarVisibility" = "auto";

      "security.workspace.trust.enabled" = true;
      
      "C_Cpp.default.compilerPath" = "gcc";

      "direnv.restart.automatic" = true;

      "nix.enableLanguageServer" = true;
      "nix.serverPath" = "nixd";
      "nix.formatterPath" = "nixfmt";
    };
  };

  home.file = {
    ".continue/config.json".text = builtins.toJSON {
      "models" = [
        {
          "model" = "o1-mini";
          "title" = "o1 Mini";
          "systemMessage" = "You are an expert software developer. You give helpful and concise responses.";
          "apiKey" = builtins.readFile config.sops.secrets.openai.path;
          "provider" = "openai";
        }
      ];
      "tabAutocompleteModel" = {
        "title" = "Codestral";
        "provider" = "mistral";
        "model" = "codestral-latest";
        "apiKey" = builtins.readFile config.sops.secrets.codestral.path;
      };
    };
  };
}