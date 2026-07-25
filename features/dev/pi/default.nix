# features/dev/pi/default.nix
# Pi coding agent — declarative, extension-driven configuration.
#
# Architecture:
#   ./                 Orchestrator: deploys AGENTS.md + skills, auto-discovers extensions
#   ./skills/          pi-core engineering harness
#   ./extensions/      One directory per extension — pure Nix options + _files contract
#
# Extension contract:
#   Each extension declares `my.features.dev.pi.extensions.<name>.*` options
#   and sets `_files.config` (attrsets → JSON) and/or `_files.assets` (dirs → deployed).
#   Extensions never touch home.file, home.activation, or SOPS logic.
#   The orchestrator handles all deployment and SOPS resolution.

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

  extensionPackageMap = {
    web-access = "npm:pi-web-access";
    mcp-adapter = "npm:pi-mcp-adapter";
    pi-lens = "npm:pi-lens";
    context-mode = "npm:context-mode";
    rpiv-questions = "npm:@juicesharp/rpiv-ask-user-question";
    pi-subagents = "npm:@tintinweb/pi-subagents";
  };

  # Recursively collect files from a directory
  collectDir =
    dir: prefix:
    let
      entries = builtins.readDir dir;
      processEntry =
        name: type:
        if type == "regular" then
          [ { relPath = (if prefix == "" then name else "${prefix}/${name}"); } ]
        else if type == "directory" then
          collectDir (dir + "/${name}") (if prefix == "" then name else "${prefix}/${name}")
        else
          [ ];
    in
    lib.concatMap (name: processEntry name entries.${name}) (builtins.attrNames entries);

  skillFiles = collectDir ./skills "";

  # ── SOPS helpers ──────────────────────────────────────────────────

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

  # Render a nested attrset as a shell heredoc fragment.
  # Literal values → JSON-baked at build time.
  # SOPS paths (/run/secrets/…) → $(cat <path>) resolved at activation time.
  renderFields =
    attrs:
    let
      renderVal =
        v:
        if lib.isString v && lib.hasPrefix "/run/secrets/" v then
          ''"$(cat ${lib.escapeShellArg v} 2>/dev/null || true)"''
        else if lib.isAttrs v then
          renderObj v
        else
          builtins.toJSON v;

      renderObj =
        obj:
        let
          fields = lib.mapAttrsToList (k: v: ''"${k}": ${renderVal v}'') obj;
        in
        "{\n    ${builtins.concatStringsSep ",\n    " fields}\n  }";
    in
    renderObj attrs;
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

    # ── Auth (SOPS) ───────────────────────────────────────

    auth = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.apiKey = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "API key or SOPS secret path (/run/secrets/…).";
          };
        }
      );
      default = { };
      description = ''
        Provider credentials. Each key is a provider name.
        Use SOPS secret paths for production:
          auth.deepseek.apiKey = config.sops.secrets."deepseek-api-key".path;
      '';
    };

    # ── Catch-all ─────────────────────────────────────────

    extraSettings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Additional settings.json fields — future-proof catch-all.";
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
          map (name: extensionPackageMap.${name} or null) enabledNames
        );

        # ── settings.json ────────────────────────────────────────

        baseSettings = {
          defaultProvider = cfg.provider;
          defaultModel = cfg.defaultModel;
          defaultThinkingLevel = cfg.thinkingLevel;
          theme = "dark";
          enableSkillCommands = true;
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
            defaultProvider = cfg.provider;
            defaultModel = cfg.defaultModel;
            defaultThinkingLevel = cfg.thinkingLevel;
            inherit packages;
            enableSkillCommands = true;
          };

        # ── Collect _files from all enabled extensions ───────────

        extOutputs = builtins.map (name: {
          inherit name;
          files = config.my.features.dev.pi.extensions.${name}._files or { };
        }) enabledNames;

        # config files: { path = "..."; content = {…}; }
        extConfigs = lib.concatMap (
          ext: lib.mapAttrsToList (path: content: { inherit path content; }) (ext.files.config or { })
        ) extOutputs;

        # asset dirs: { path = "..."; source = ./agents; }
        extAssets = lib.concatMap (
          ext: lib.mapAttrsToList (path: source: { inherit path source; }) (ext.files.assets or { })
        ) extOutputs;

        # ── Separate SOPS from non-SOPS config files ─────────────

        sopsConfigs = builtins.filter (f: hasSopsSecret f.content) extConfigs;
        staticConfigs = builtins.filter (f: !hasSopsSecret f.content) extConfigs;

        # ── Home-manager: static files (settings, AGENTS, skills, ext configs, assets) ──

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

        # ── Home-manager: activation scripts (SOPS configs + auth) ──

        # Auth providers (from cfg.auth, filtered to non-null apiKeys)
        authAttrs = lib.mapAttrs' (
          provider: cred:
          lib.nameValuePair provider {
            type = "api_key";
            key = cred.apiKey;
          }
        ) (lib.filterAttrs (_: cred: cred.apiKey != null) cfg.auth);

        hasAuth = authAttrs != { };

        # Combine extension SOPS configs + auth (if configured)
        sopsActivation =
          (builtins.listToAttrs (
            map (f: {
              name = "pi-sops-${builtins.hashString "md5" f.path}";
              value =
                let
                  rendered = renderFields f.content;
                in
                ''
                  mkdir -p "$(dirname "$HOME/${f.path}")"
                  cat > "$HOME/${f.path}" <<PIEOF
                  ${rendered}
                  PIEOF
                  chmod 600 "$HOME/${f.path}"
                '';
            }) sopsConfigs
          ))
          // lib.optionalAttrs hasAuth {
            "pi-auth" =
              let
                rendered = renderFields authAttrs;
              in
              ''
                mkdir -p "$HOME/.pi/agent"
                cat > "$HOME/.pi/agent/auth.json" <<PIEOF
                ${rendered}
                PIEOF
                chmod 600 "$HOME/.pi/agent/auth.json"
              '';
          };
      in
      {
        environment.systemPackages = [
          pkgs.pi-coding-agent
          pkgs.nodejs # Required for pi extension npm install operations
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
