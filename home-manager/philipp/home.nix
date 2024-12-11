{
  lib,
  config,
  pkgs,
  ...
}:

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
  systemd.user.startServices = "sd-switch";
  programs.home-manager.enable = true;

  sops = {
    age.keyFile = "/home/philipp/.config/sops/age/key.txt"; # must have no password!
    # It's also possible to use a ssh key, but only when it has no password:
    #age.sshKeyPaths = [ "/home/user/path-to-ssh-key" ];
    defaultSopsFile = ../../secrets/main.yaml;
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
    pkgs.nixd
    pkgs.nixfmt-rfc-style
    (pkgs.callPackage ../../packages/lychee-slicer { })
  ];

  programs.bash = {
    enable = true;
    enableCompletion = true;
  };

  dconf = {
    enable = true;
    settings = {
      "org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
        accent-color = "green";
        enable-hot-corners = true;
      };

      "org/gnome/shell" = {
        disable-user-extensions = false;
        enabled-extensions = with pkgs.gnomeExtensions; [
          blur-my-shell.extensionUuid
          gsconnect.extensionUuid
          caffeine.extensionUuid
          dash-to-dock.extensionUuid
        ];
        favorite-apps = [
          "org.gnome.Nautilus.desktop"
          "codium.desktop"
          "spotify.desktop"
          "obsidian.desktop"
          "google-chrome.desktop"
          "com.raggesilver.BlackBox.desktop"
        ];
      };
      #blur dash-to-dock shell
      "org/gnome/shell/extensions/blur-my-shell/dash-to-dock" = {
        blur = true;
      };

      "org/gnome/shell/extensions/dash-to-dock" = {
        apply-custom-theme = true;
      };

      "com/raggesilver/BlackBox" = {
        command-as-login-shell = true;
        context-aware-header-bar = true;
        delay-before-showing-floating-controls = 200;
        easy-copy-paste = true;
        fill-tabs = true;
        floating-controls = true;
        floating-controls-hover-area = 20;
        notify-process-complition = false;
        opacity = 1;
        show-headerbar = false;
        terminal-padding =
          with lib.hm.gvariant;
          mkTuple [
            (mkUint32 15)
            (mkUint32 15)
            (mkUint32 15)
            (mkUint32 15)
          ];
      };
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
      jnoortheen.nix-ide
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

      "nix.enableLanguageServer" = true;
      "nix.serverPath" = "nixd";
      "nix.formatterPath" = "nixfmt";
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
