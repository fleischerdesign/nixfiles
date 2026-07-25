# features/dev/pi/default.nix
# Pi coding agent — declarative, extension-driven configuration.
#
# Architecture:
#   ./                 Orchestrator: deploys AGENTS.md + skills, auto-discovers extensions
#   ./skills/          pi-core engineering harness
#   ./extensions/      One directory per extension — pure Nix options + _files contract
#   ./lib/             Shared types (extension-files, extra-settings)
#
# Extension contract:
#   Each extension declares `my.features.dev.pi.extensions.<name>.*` options
#   and sets `_files.config` (attrsets → JSON) and/or `_files.assets` (dirs → deployed).
#   Extensions never touch home.file, home.activation, or SOPS logic.
#   The orchestrator handles all deployment and SOPS resolution.
#
# Auth:
#   Provider API keys are resolved via pi's native `!cat` shell-command syntax
#   (pi's resolveConfigValue resolution step 2). No activation scripts, no
#   shell heredocs — the key field in auth.json is a static string.
#
# Extension configs with SOPS values:
#   Values referencing /run/secrets/… are rendered as $(cat <path>) in a shell
#   heredoc activation script. This is the only activation script remaining.

{
  config,
  lib,
  pkgs,
  ...
}:

let
  extensionsDir = ./extensions;

  extensionNames =
    let
      entries = builtins.readDir extensionsDir;
    in
    lib.filter (
      name: entries.${name} == "directory" && builtins.pathExists (extensionsDir + "/${name}/default.nix")
    ) (builtins.attrNames entries);

  # Recursively collect files from a directory
  collectDir =
    dir: prefix:
    let
      entries = builtins.readDir dir;
      processEntry =
        name: type:
        if type == "regular" then
          [ { relPath = if prefix == "" then name else "${prefix}/${name}"; } ]
        else if type == "directory" then
          collectDir (dir + "/${name}") (if prefix == "" then name else "${prefix}/${name}")
        else
          [ ];
    in
    lib.concatMap (name: processEntry name entries.${name}) (builtins.attrNames entries);

  skillFiles = collectDir ./skills "";

  # ── SOPS helpers (extension configs only — auth uses pi-native !cat) ──

  # True if any leaf string value in the attrset starts with /run/secrets/
  hasSopsSecret =
    attrs:
    lib.any (
      v:
      if lib.isString v then
        lib.hasPrefix "/run/secrets/" v
      else if lib.isAttrs v then
        hasSopsSecret v
      else
        false
    ) (builtins.attrValues attrs);

  # Render an attrset as a shell heredoc fragment for SOPS-resolved values.
  # Literal values → JSON-baked. SOPS paths → $(cat <path>) resolved at activation.
  renderConfig =
    attrs:
    let
      renderVal =
        v:
        if lib.isString v && lib.hasPrefix "/run/secrets/" v then
          ''"$(cat ${lib.escapeShellArg v})"''
        else if lib.isAttrs v then
          throw "nested objects in extension config SOPS not supported — flatten your config"
        else
          builtins.toJSON v;

      fields = lib.mapAttrsToList (k: v: ''"${k}": ${renderVal v}'') attrs;
    in
    ''
      {
            ${lib.concatStringsSep "\n,   " fields}
          }'';

  # ── Auth helpers ───────────────────────────────────────────────────────

  # Convert a SOPS secret path to pi's native !cat shell-command syntax.
  # Pi resolves !command in auth.json keys at runtime (resolveConfigValue step 2).
  toAuthKey =
    key: if lib.isString key && lib.hasPrefix "/run/secrets/" key then "!cat ${key}" else key;
in
{
  imports = map (name: extensionsDir + "/${name}/default.nix") extensionNames;

  options.my.features.dev.pi = {
    enable = lib.mkEnableOption "pi coding agent with the full engineering harness";

    # ── Model & Provider ──────────────────────────────────

    provider = lib.mkOption {
      type = lib.types.str;
      default = "deepseek";
      description = "Default LLM provider (deepseek, anthropic, openai, etc.).";
    };

    defaultModel = lib.mkOption {
      type = lib.types.str;
      default = "deepseek-v4-pro";
      description = "Default model ID.";
    };

    thinkingLevel = lib.mkOption {
      type = lib.types.enum [
        "off"
        "minimal"
        "low"
        "medium"
        "high"
        "xhigh"
        "max"
      ];
      default = "high";
      description = "Default thinking/reasoning level.";
    };

    enabledModels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Model patterns for Ctrl+P cycling (e.g. [\"deepseek-*\"]).";
    };

    # ── UI ───────────────────────────────────────────────

    theme = lib.mkOption {
      type = lib.types.enum [
        "dark"
        "light"
      ];
      default = "dark";
      description = "Pi UI theme.";
    };

    enableSkillCommands = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable /skill-name slash commands.";
    };

    # ── Auth ─────────────────────────────────────────────

    auth = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.apiKey = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = ''
              API key or SOPS secret path.  For SOPS secrets, use the !cat
              resolution path (e.g. config.sops.secrets."deepseek-key".path).
              Pi will resolve the secret at runtime via !cat <path>.
            '';
          };
        }
      );
      default = { };
    };

    # ── Catch-all ─────────────────────────────────────────

    extraSettings = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.oneOf [
          lib.types.str
          lib.types.int
          lib.types.bool
        ]
      );
      default = { };
      description = "Additional settings.json fields (flat scalars only).";
    };
  };

  config = lib.mkMerge [
    # Default all extensions to enabled
    {
      my.features.dev.pi.extensions = lib.genAttrs extensionNames (_: {
        enable = lib.mkDefault true;
      });
    }

    (lib.mkIf config.my.features.dev.pi.enable (
      let
        cfg = config.my.features.dev.pi;

        enabledNames = lib.filter (
          name: config.my.features.dev.pi.extensions.${name}.enable or false
        ) extensionNames;

        packages = builtins.filter (p: p != null) (
          map (name: config.my.features.dev.pi.extensions.${name}.package or null) enabledNames
        );

        # ── settings.json ────────────────────────────────────────

        baseSettings = {
          inherit (cfg)
            defaultProvider
            defaultModel
            defaultThinkingLevel
            theme
            enableSkillCommands
            ;
          inherit packages;
        }
        // lib.optionalAttrs (cfg.enabledModels != [ ]) {
          enabledModels = cfg.enabledModels;
        };

        mergedSettings =
          let
            overlaid = lib.recursiveUpdate baseSettings cfg.extraSettings;
          in
          overlaid
          // {
            inherit packages;
            inherit (cfg)
              defaultProvider
              defaultModel
              defaultThinkingLevel
              theme
              enableSkillCommands
              ;
          };

        # ── Collect _files from all enabled extensions ───────────

        extOutputs = builtins.map (
          name:
          let
            ext = config.my.features.dev.pi.extensions.${name};
          in
          {
            inherit name;
            files = ext._files or { };
          }
        ) enabledNames;

        # config files: { path = "..."; content = {…}; }
        extConfigs = lib.concatMap (
          ext: lib.mapAttrsToList (path: content: { inherit path content; }) (ext.files.config or { })
        ) extOutputs;

        # asset dirs: { path = "..."; source = <dir>; }
        extAssets = lib.concatMap (
          ext: lib.mapAttrsToList (path: source: { inherit path source; }) (ext.files.assets or { })
        ) extOutputs;

        # ── Separate SOPS from non-SOPS config files ─────────────

        sopsConfigs = builtins.filter (f: hasSopsSecret f.content) extConfigs;
        staticConfigs = builtins.filter (f: !hasSopsSecret f.content) extConfigs;

        # ── Home-manager: static files ───────────────────────────

        # Extension JSON configs (no SOPS)
        extConfigFiles = builtins.listToAttrs (
          map (f: {
            name = f.path;
            value = {
              text = builtins.toJSON f.content;
            };
          }) staticConfigs
        );

        # Extension assets (verbatim)
        extAssetFiles = builtins.listToAttrs (
          map (f: {
            name = f.path;
            value = {
              source = f.source;
              recursive = true;
            };
          }) extAssets
        );

        # ── Auth (pi-native !cat, static file) ──────────────────

        authAttrs = lib.mapAttrs' (
          provider: cred:
          lib.nameValuePair provider {
            type = "api_key";
            key = toAuthKey cred.apiKey;
          }
        ) (lib.filterAttrs (_: cred: cred.apiKey != null) cfg.auth);

        # ── Home-manager: activation scripts (SOPS extension configs) ──

        sopsActivation = builtins.listToAttrs (
          map (f: {
            name = "pi-sops-${builtins.hashString "md5" f.path}";
            value =
              let
                rendered = renderConfig f.content;
              in
              ''
                mkdir -p "$(dirname "$HOME/${f.path}")"
                cat > "$HOME/${f.path}" <<PIEOF
                ${rendered}
                PIEOF
                chmod 600 "$HOME/${f.path}"
              '';
          }) sopsConfigs
        );
      in
      {
        environment.systemPackages = [
          pkgs.pi-coding-agent
          pkgs.nodejs
        ];

        home-manager.users = lib.mkIf (config.my.user.name or null != null) {
          ${config.my.user.name} = {
            home.file =
              # settings.json
              {
                ".pi/agent/settings.json".text = builtins.toJSON mergedSettings;
              }
              # AGENTS.md
              // {
                ".pi/agent/AGENTS.md".source = ./AGENTS.md;
              }
              # skills/
              // builtins.listToAttrs (
                map (f: {
                  name = ".pi/agent/skills/${f.relPath}";
                  value = {
                    source = ./skills + "/${f.relPath}";
                  };
                }) skillFiles
              )
              # auth.json (static — pi resolves !cat at runtime)
              // (lib.optionalAttrs (authAttrs != { }) {
                ".pi/agent/auth.json" = {
                  text = builtins.toJSON authAttrs;
                };
              })
              # Extension static config JSON
              // extConfigFiles
              # Extension assets
              // extAssetFiles;

            home.activation = sopsActivation;
          };
        };
      }
    ))
  ];
}
