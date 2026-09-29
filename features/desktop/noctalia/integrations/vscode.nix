# VS Code. The theme extension is installed from the marketplace, but the generated
# palette must be written inside its own directory, which VS Code only accepts as a
# mutable extensions directory: `mutableExtensionsDir` therefore overrides the editor
# feature's immutable choice for this host. The two files that identify the extension
# stay Home Manager-owned; the theme file is seeded once and owned by Noctalia after.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.desktop.noctalia;

  theme = pkgs.vscode-marketplace.noctalia.noctaliatheme;
  extensionId = "noctalia.noctaliatheme";
  extensionDir = "${extensionId}-${theme.version}";
  extensionSource = "${theme}/share/vscode/extensions/${extensionId}";
  extensionTarget = "${config.home.homeDirectory}/.vscode/extensions/${extensionDir}";
in
{
  config = lib.mkIf (cfg.enable && config.programs.vscode.enable) {
    programs.noctalia.settings.theme.templates.community_ids = [ "vscode" ];

    programs.vscode = {
      mutableExtensionsDir = lib.mkForce true;
      profiles.default.userSettings."workbench.colorTheme" = "NoctaliaTheme";
    };

    home.file = {
      ".vscode/extensions/${extensionDir}/package.json".source = "${extensionSource}/package.json";
      ".vscode/extensions/${extensionDir}/noctalialogo.png".source =
        "${extensionSource}/noctalialogo.png";
    };

    # A Home Manager generation that managed the extensions directory immutably left
    # `~/.vscode/extensions` as a symlink into the store, and the mutable layout below
    # cannot create a directory inside it. Remove exactly that link before linkGeneration
    # recreates the directory; a real directory or a foreign link is never touched.
    home.activation.noctaliaVSCodeExtensionDir =
      lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ]
        ''
          if [ -L "$HOME/.vscode/extensions" ]; then
            case "$(readlink -f "$HOME/.vscode/extensions")" in
              /nix/store/*) rm -- "$HOME/.vscode/extensions" ;;
            esac
          fi
        '';

    # Noctalia takes ownership of the theme file from the first render on; the seed only
    # has to exist so VS Code can discover the extension before that render happens.
    home.activation.seedNoctaliaVSCodeTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      target=${lib.escapeShellArg "${extensionTarget}/themes/NoctaliaTheme-color-theme.json"}
      if [ ! -e "$target" ]; then
        mkdir -p "$(dirname "$target")"
        cp -- ${lib.escapeShellArg "${extensionSource}/themes/NoctaliaTheme-color-theme.json"} "$target"
        chmod u+w "$target"
      fi
    '';
  };
}
