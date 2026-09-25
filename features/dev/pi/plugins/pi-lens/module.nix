# features/dev/pi/plugins/pi-lens/module.nix
# Real-time code feedback for pi: LSP, linters, formatters, type-checking, structural analysis.
#
# Architecture & Guidelines:
# - Agnostic & Extensible: Language presets provide high-signal defaults, while `servers` allows custom additions.
# - DRY & Hermetic: Declaring a server installs its package, registers its binary, and writes its ~/.pi-lens/config.json entry.
# - Explicit Store Paths: Servers are wired to absolute ${package}/bin/${binName} store paths.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.dev.pi.plugins.pi-lens;
  piCfg = config.my.features.dev.pi;

  serverSubmodule = lib.types.submodule {
    options = {
      package = lib.mkOption {
        type = lib.types.package;
        description = "LSP executable package added to user closure.";
      };
      binName = lib.mkOption {
        type = lib.types.str;
        description = "Executable name under the package bin/ directory.";
      };
      extensions = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = "List of file extensions handled by this LSP server.";
      };
      args = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Command-line arguments passed to the language server.";
      };
      initializationOptions = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        description = "Initialization options sent to the LSP server.";
      };
    };
  };

  # Built-in presets for developer languages:
  # Rust, Go, Csharp, HTML, CSS, Zig, Java, Python, TypeScript, JavaScript, Nix
  presetServers =
    lib.optionalAttrs cfg.languages.nix.enable {
      nil = {
        package = pkgs.nil;
        binName = "nil";
        extensions = [ ".nix" ];
        args = [ ];
      };
    }
    // lib.optionalAttrs cfg.languages.rust.enable {
      rust-analyzer = {
        package = pkgs.rust-analyzer;
        binName = "rust-analyzer";
        extensions = [ ".rs" ];
        args = [ ];
      };
    }
    // lib.optionalAttrs cfg.languages.go.enable {
      gopls = {
        package = pkgs.gopls;
        binName = "gopls";
        extensions = [ ".go" ];
        args = [ ];
      };
    }
    // lib.optionalAttrs cfg.languages.zig.enable {
      zls = {
        package = pkgs.zls;
        binName = "zls";
        extensions = [ ".zig" ];
        args = [ ];
      };
    }
    // lib.optionalAttrs cfg.languages.python.enable {
      pyright = {
        package = pkgs.pyright;
        binName = "pyright-langserver";
        extensions = [ ".py" ];
        args = [ "--stdio" ];
      };
    }
    // lib.optionalAttrs (cfg.languages.typescript.enable || cfg.languages.javascript.enable) {
      typescript-language-server = {
        package = pkgs.typescript-language-server;
        binName = "typescript-language-server";
        extensions = [
          ".ts"
          ".tsx"
          ".js"
          ".jsx"
          ".mjs"
          ".cjs"
        ];
        args = [ "--stdio" ];
      };
    }
    // lib.optionalAttrs cfg.languages.html.enable {
      vscode-html-language-server = {
        package = pkgs.vscode-langservers-extracted;
        binName = "vscode-html-language-server";
        extensions = [
          ".html"
          ".htm"
        ];
        args = [ "--stdio" ];
      };
    }
    // lib.optionalAttrs cfg.languages.css.enable {
      vscode-css-language-server = {
        package = pkgs.vscode-langservers-extracted;
        binName = "vscode-css-language-server";
        extensions = [
          ".css"
          ".scss"
          ".less"
        ];
        args = [ "--stdio" ];
      };
    }
    // lib.optionalAttrs cfg.languages.csharp.enable {
      csharp-ls = {
        package = pkgs.csharp-ls;
        binName = "csharp-ls";
        extensions = [ ".cs" ];
        args = [ ];
      };
    }
    // lib.optionalAttrs cfg.languages.java.enable {
      jdtls = {
        package = pkgs.jdt-language-server;
        binName = "jdtls";
        extensions = [ ".java" ];
        args = [ ];
      };
    };

  allActiveServers = presetServers // cfg.servers;
in
{
  options.my.features.dev.pi.plugins.pi-lens = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable pi-lens code-feedback and LSP diagnostics plugin.";
    };

    languages = {
      nix.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Nix language server (nil) and linters.";
      };
      rust.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Rust language server (rust-analyzer).";
      };
      go.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Go language server (gopls).";
      };
      zig.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Zig language server (zls).";
      };
      python.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Python language server (pyright).";
      };
      typescript.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable TypeScript language server.";
      };
      javascript.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable JavaScript language server support.";
      };
      html.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable HTML language server.";
      };
      css.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable CSS language server.";
      };
      csharp.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable C# language server (csharp-ls).";
      };
      java.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Java language server (jdtls).";
      };
    };

    servers = lib.mkOption {
      type = lib.types.attrsOf serverSubmodule;
      default = { };
      description = "Custom or override LSP server specifications.";
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Additional raw options merged into ~/.pi-lens/config.json.";
    };
  };

  config = lib.mkIf (piCfg.enable && cfg.enable) {
    # Ensure all required LSP packages and linters are materialized in the user environment
    my.features.dev.pi.cliPackages =
      lib.catAttrs "package" (lib.attrValues allActiveServers)
      ++ lib.optionals cfg.languages.nix.enable [
        pkgs.statix
        pkgs.deadnix
      ];

    home-manager.sharedModules = [
      (
        {
          config,
          lib,
          ...
        }:
        let
          userPiCfg = config.my.features.dev.pi;

          renderedServers = lib.mapAttrs (
            name: s:
            {
              inherit name;
              inherit (s) extensions args;
              command = "${s.package}/bin/${s.binName}";
              enabled = true;
            }
            // lib.optionalAttrs ((s.initializationOptions or { }) != { }) {
              inherit (s) initializationOptions;
            }
          ) allActiveServers;

          baseConfig = {
            lsp = {
              servers = renderedServers;
            };
          };

          mergedConfig = lib.recursiveUpdate baseConfig cfg.extraConfig;
        in
        {
          config = lib.mkIf userPiCfg.enable {
            home.file.".pi-lens/config.json".text = builtins.toJSON mergedConfig;
          };
        }
      )
    ];
  };
}
