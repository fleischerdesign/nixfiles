{ lib, config, pkgs, inputs, ... }:

{
  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "philipp";
  home.homeDirectory = "/home/philipp"; 

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "24.05";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

    sops = {
    age.keyFile = "/home/philipp/.config/sops/age/key.txt"; # must have no password!
    # It's also possible to use a ssh key, but only when it has no password:
    #age.sshKeyPaths = [ "/home/user/path-to-ssh-key" ];
    defaultSopsFile = ../../secrets/example.yaml;
    secrets.openai = { };
    secrets.codestral = { };
    };

  home.packages = [
    pkgs.google-chrome
    pkgs.spotify
    pkgs.gnomeExtensions.blur-my-shell
    pkgs.gnomeExtensions.gsconnect
    pkgs.gnomeExtensions.caffeine
    pkgs.gnomeExtensions.dash-to-dock
    pkgs.gimp
    pkgs.blackbox-terminal
    pkgs.figma-linux
    #pkgs.figma-agent
    pkgs.obsidian
    pkgs.orca-slicer
    (pkgs.callPackage ../../packages/lychee-slicer {})
  ];

  programs.bash = {
    enable = true;
    enableCompletion = true;
  };

  programs.starship = {
    enable = true;
    settings = {
          # add_newline = false;

          # character = {
          #   success_symbol = "[➜](bold green)";
          #   error_symbol = "[➜](bold red)";
          # };

          # package.disabled = true;
        };
  };

  dconf = {
    enable = true;

    settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";

    settings."org/gnome/shell" = {
      disable-user-extensions = false;
      enabled-extensions = with pkgs.gnomeExtensions; [
        blur-my-shell.extensionUuid
        gsconnect.extensionUuid
        caffeine.extensionUuid
        dash-to-dock.extensionUuid
      ];
    };
  };

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
    ];
    userSettings = {
      "git.confirmSync" = false;
      "git.autofetch" = true;
      "terminal.integrated.fontFamily" = "nerd-font-symbols";
      "terminal.integrated.fontWeight" = "normal";

      "window.titleBarStyle" = "custom";
      "window.customTitleBarVisibility" = "auto";

      "C_Cpp.default.compilerPath" = "gcc";

      "direnv.restart.automatic" = true;
    };
  };
  home.file = {
    ".continue/config.json".text = builtins.toJSON {
      "models" = [
        {
          "model" = "gpt-4o-mini";
          "title" = "GPT-4o Mini";
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
