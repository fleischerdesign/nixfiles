{pkgs, ...}:
{
    home.sessionVariables = {
    EDITOR = "codium";
  };



  programs.vscode = {
    enable = true;
    package = pkgs.vscodium;
    mutableExtensionsDir = false;
    profiles.default = {
      extensions = with pkgs.vscode-extensions; [
        prisma.prisma
        vue.volar
        mkhl.direnv
        ms-vscode.cpptools
        jnoortheen.nix-ide
        dart-code.flutter
        dart-code.dart-code
        rooveterinaryinc.roo-cline
        redhat.java
        vscjava.vscode-java-debug
        vscjava.vscode-java-test
        vscjava.vscode-java-dependency
        visualstudioexptteam.vscodeintellicode
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
        "dart.renameFilesWithClasses" = "prompt";
        "dart.previewFlutterUiGuides" = true;

        "chat.agent.enabled" = true;

        "redhat.telemetry.enabled" = false;
      };
    };
  };
}
