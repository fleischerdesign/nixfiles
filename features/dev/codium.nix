# features/dev/codium.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.dev.codium;
in
{
  options.my.features.dev.codium = {
    enable = lib.mkEnableOption "VSCodium with extensions";
  };

  config = lib.mkIf cfg.enable {
    home-manager.sharedModules = [{
      programs.vscode = {
        enable = true;
        package = pkgs.vscodium;
        mutableExtensionsDir = false;

        profiles.default = {
          extensions = with pkgs.vscode-marketplace; [
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
            bbenoist.qml
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
    }];
  };
}
