{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf config.my.homeManager.modules.codium.enable {
    programs.vscode = {
      enable = true;
      package = pkgs.vscodium;
      mutableExtensionsDir = false;

      profiles.default = {
        extensions = with pkgs.vscode-extensions; [
          prisma.prisma
          bradlc.vscode-tailwindcss
          vue.volar
          mkhl.direnv
          ms-vscode.cpptools
          jnoortheen.nix-ide
          dart-code.flutter
          dart-code.dart-code
          redhat.java
          vscjava.vscode-java-debug
          vscjava.vscode-java-test
          vscjava.vscode-java-dependency
          visualstudioexptteam.vscodeintellicode
          dbaeumer.vscode-eslint
        ];
        userSettings = {
          "extensions.autoUpdate" = false;
          "git.confirmSync" = false;
          "git.autofetch" = true;
          "terminal.integrated.fontWeight" = "normal";

          "terminal.integrated.persistentSessionReviveProcess" = "never";

          "update.mode" = "none";

          "window.titleBarStyle" = "custom";
          "window.customTitleBarVisibility" = "auto";

          "security.workspace.trust.enabled" = true;

          "C_Cpp.default.compilerPath" = "gcc";

          "direnv.restart.automatic" = true;

          "nix.enableLanguageServer" = true;
          "nix.serverPath" = "nil";
          "nix.formatterPath" = "nixfmt";
          "dart.renameFilesWithClasses" = "prompt";
          "dart.previewFlutterUiGuides" = true;

          "chat.agent.enabled" = true;

          "redhat.telemetry.enabled" = false;

          "editor.formatOnSave" = true;
        };
      };
    };
  };
}
