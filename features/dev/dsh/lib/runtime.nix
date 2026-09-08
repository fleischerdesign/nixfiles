# features/dev/dsh/lib/runtime.nix — Shared dsh configuration-document runtime.
#
# Single source of truth for the option → dsh-document computation, shared by
# BOTH the NixOS system level (credential records, system service, and the
# /var/lib/dsh materialization) and the Home-Manager user level (the per-user
# ~/.dsh materialization). Hoisting this out of the home-manager.sharedModules
# let keeps the two surfaces byte-identical and lets the system level render
# the same documents without duplication.
#
# Inputs:
#   systemCfg  — the NixOS option set my.features.dev.dsh (options, not the
#                resolved home-manager user config).
#   osConfig   — the parent NixOS config (topology, sops, ...).
#   userCfg    — the home-manager user option set my.features.dev.dsh (default
#                {} when rendering at system level, which contributes no
#                user-specific settings/facts/peers).
#   currentUser- resolved operator identity (osConfig.my.user.name at system
#                level; defaulted inside).
#
# Returns the full rendered runtime attrset consumed by both surfaces.
{
  lib,
  render,
  pluginsLib,
  pkgs,
}:
let
  mkDshRuntime =
    {
      systemCfg,
      osConfig ? { },
      userCfg ? { },
      currentUser ? null,
    }:
    let
      mcpServers = systemCfg.mcpServers or { };

      # --- Active plugins (system-level switches) ---
      activePluginNames = lib.filter (
        name: (systemCfg.plugins.${name}.enable or true)
      ) pluginsLib.pluginNames;
      activePluginDrvs = map (name: pluginsLib.derivations.${name}) activePluginNames;
      activePluginBundleNames = map (name: pluginsLib.bundleNameOf name) activePluginNames;

      dshPackage = if systemCfg.package or null != null then systemCfg.package else pkgs.custom.dsh;

      # --- Settings document ($DSH_HOME/settings.yaml) ---
      baseSettings = render.mkBaseSettings systemCfg;
      settingsDoc = lib.recursiveUpdate (lib.recursiveUpdate baseSettings (systemCfg.settings or { })) (
        userCfg.settings or { }
      );

      # --- Identity ---
      topologyHosts = osConfig.my.features.system.networking.topology.hosts or { };
      currentHost = osConfig.networking.hostName or "unknown";
      effectiveUser =
        if currentUser != null then currentUser else (osConfig.my.user.name or (builtins.getEnv "USER"));

      # --- Invariant memory facts: topology + system + user personal ---
      topologyFacts = lib.flatten (
        lib.mapAttrsToList (hostname: host: [
          {
            subject = "urn:nix:host:${hostname}";
            predicate = "sys:hasType";
            object = host.hostType or "client";
          }
          (lib.optional (host.tailscaleIp != null) {
            subject = "urn:nix:host:${hostname}";
            predicate = "net:tailscaleIp";
            object = host.tailscaleIp;
            type_constraint = "IPv4";
          })
          (lib.optional (host.domain != null) {
            subject = "urn:nix:host:${hostname}";
            predicate = "net:domain";
            object = host.domain;
            type_constraint = "FQDN";
          })
        ]) topologyHosts
      );

      allConfiguredFacts =
        topologyFacts
        ++ (systemCfg.memory.facts or [ ])
        ++ (map (
          f:
          f
          // {
            scope_id = if f.scope_id != null then f.scope_id else "user:${effectiveUser}";
          }
        ) (userCfg.memory.userFacts or [ ]));

      # --- Mesh peers ---
      topologyPeers = lib.flatten (
        lib.mapAttrsToList (
          hostname: host:
          lib.optional (hostname != currentHost && host.tailscaleIp != null) {
            id = hostname;
            endpoint = "${host.tailscaleIp}:${toString (systemCfg.mesh.listenPort or 3891)}";
            tags = [ (host.hostType or "client") ];
            scope = "system";
          }
        ) topologyHosts
      );
      systemExplicitPeers = map (p: p // { scope = "system"; }) (systemCfg.mesh.peers or [ ]);
      systemGroupPeers = lib.flatten (
        lib.mapAttrsToList (
          groupName: peersList:
          map (
            p:
            p
            // {
              scope = "group";
              group = groupName;
            }
          ) peersList
        ) (systemCfg.mesh.groupPeers or { })
      );
      userPersonalPeers = map (
        p:
        p
        // {
          scope = "user";
          owner = effectiveUser;
        }
      ) (userCfg.mesh.userPeers or [ ]);
      allConfiguredPeers = topologyPeers ++ systemExplicitPeers ++ systemGroupPeers ++ userPersonalPeers;

      # --- Plugin configs ---
      authCfg = systemCfg.auth or { };
      pluginConfigs = {
        "dsh-auth" = {
          mode = authCfg.mode or "auto";
          forwardProxy = authCfg.forwardProxy or { enabled = true; };
          oidc = authCfg.oidc or { enabled = false; };
          ldap = authCfg.ldap or { enabled = false; };
          loopback = {
            enabled = authCfg.loopback.enabled or true;
            defaultUser = effectiveUser;
            defaultClearance = "Admin";
          };
          peerMesh = authCfg.peerMesh or { enabled = true; };
        };
        "dsh-memory" = {
          facts = allConfiguredFacts;
          maxRecallTokens = systemCfg.memory.maxRecallTokens or 150;
          minRecallThreshold = systemCfg.memory.minRecallThreshold or (-1.5);
        }
        // (
          if systemCfg.memory.embedding.enable or false then
            {
              embedding = {
                inherit (systemCfg.memory.embedding)
                  provider
                  dim
                  minSimilarity
                  topK
                  similarityMargin
                  weight
                  entropyMinStems
                  batchSize
                  ;
                modelDir = systemCfg.memory.embedding.modelDir or null;
                modelId = systemCfg.memory.embedding.modelId or null;
                apiBase = systemCfg.memory.embedding.apiBase or null;
                apiModel = systemCfg.memory.embedding.apiModel or null;
                apiKeyEnv = systemCfg.memory.embedding.apiKeyEnv or null;
              };
            }
          else
            { }
        )
        // (
          if systemCfg.memory.replication.enable or false then
            {
              replication = {
                inherit (systemCfg.memory.replication)
                  enable
                  secretEnv
                  listenHost
                  syncIntervalMs
                  maxVersionsPerSync
                  ;
                nodeId = systemCfg.memory.replication.nodeId or currentHost;
                tenantContext = systemCfg.memory.replication.tenantContext or "user:${effectiveUser}";
                scopes = systemCfg.memory.replication.scopes or [ "public" ];
                listenPort = systemCfg.memory.replication.listenPort or null;
                peers = map (p: {
                  inherit (p)
                    nodeId
                    endpoint
                    direction
                    scopes
                    ;
                }) (systemCfg.memory.replication.peers or [ ]);
              };
            }
          else
            { }
        )
        // (
          if systemCfg.memory.decay.enable or false then
            {
              decay = {
                inherit (systemCfg.memory.decay)
                  halfLifeSeconds
                  floor
                  retentionSeconds
                  vacuumIntervalSeconds
                  ;
              };
            }
          else
            { }
        );
        "dsh-mesh" = {
          nodeId = currentHost;
          listenPort = systemCfg.mesh.listenPort or 3891;
          peers = allConfiguredPeers;
        };
      };

      # --- LSP (system level) ---
      lspCfg = systemCfg.lsp or { };
      lspEnabled = lspCfg.enable or false;
      activeLspServers = lib.filterAttrs (_: s: s.enable) (lspCfg.servers or { });
      lspConfiguredServers = lib.mapAttrs (
        _: server:
        render.optionalFields {
          command =
            if server.command != null then
              server.command
            else if server.package != null then
              "${server.package}/bin/${
                server.package.meta.mainProgram or server.package.pname or server.package.name
              }"
            else
              null;
          extensionToLanguage = server.extensionToLanguage;
          args = if server.args == [ ] then null else server.args;
          env = if server.env == { } then null else server.env;
          initializationOptions = server.initializationOptions;
          configuration = server.configuration;
          maxMessageBytes = server.maxMessageBytes;
          maxStderrBytes = server.maxStderrBytes;
          maxDocumentBytes = server.maxDocumentBytes;
          shutdownTimeoutMs = server.shutdownTimeoutMs;
          killGraceMs = server.killGraceMs;
        }
      ) activeLspServers;
      lspPatchEntries = lib.optionals (lspEnabled && lspConfiguredServers != { }) [
        (render.mkEntry "lsp" "@deepseek-ai/dsh-lsp" { })
        (render.mkEntry "lsp-stdio" "@deepseek-ai/dsh-lsp-stdio" {
          servers = lspConfiguredServers;
        })
        (render.mkEntry "tool-lsp" "@deepseek-ai/dsh-tool-lsp" (
          render.optionalFields {
            maxLocations = lspCfg.maxLocations;
            maxResultChars = lspCfg.maxResultChars;
            timeoutMs = lspCfg.timeoutMs;
          }
        ))
      ];

      # --- Patch layer ($DSH_HOME/cordis.patch.yml) ---
      patchEntries = render.mkHomePatchEntries {
        inherit mcpServers pluginConfigs;
        persona = systemCfg.persona or null;
        pluginBundleNames = activePluginBundleNames;
        extraEntries = lspPatchEntries;
      };
      homePatch = render.mkHomePatch patchEntries;

      # --- Profiles ---
      renderedProfiles = systemCfg.profiles or { };
    in
    {
      inherit
        mcpServers
        activePluginNames
        activePluginDrvs
        activePluginBundleNames
        dshPackage
        baseSettings
        settingsDoc
        topologyFacts
        allConfiguredFacts
        currentHost
        effectiveUser
        topologyPeers
        systemExplicitPeers
        systemGroupPeers
        userPersonalPeers
        allConfiguredPeers
        authCfg
        pluginConfigs
        lspCfg
        lspEnabled
        activeLspServers
        lspConfiguredServers
        lspPatchEntries
        patchEntries
        homePatch
        renderedProfiles
        ;
    };

  # Build a store derivation that materializes the full dsh configuration
  # document set (settings.yaml, cordis.patch.yml, profiles/, and the
  # node_modules plugin symlinks) under $out/. The caller (NixOS-level
  # /var/lib/dsh seed) installs these contents; because this uses the SAME
  # mkDshRuntime documents as the Home-Manager ~/.dsh materialization, the two
  # surfaces are byte-identical by construction.
  mkDshRuntimeSeed =
    {
      systemCfg,
      osConfig ? { },
      userCfg ? { },
      currentUser ? null,
    }:
    let
      rt = mkDshRuntime {
        inherit
          systemCfg
          osConfig
          userCfg
          currentUser
          ;
      };
      dshPackage = rt.dshPackage;

      # (relative-path → text) for every text document rendered in the seed.
      textDocs = [
        {
          path = "settings.yaml";
          text = builtins.toJSON rt.settingsDoc;
        }
      ]
      ++ lib.optionals (rt.homePatch != null) [
        {
          path = "cordis.patch.yml";
          text = rt.homePatch;
        }
      ]
      ++ lib.flatten (
        lib.mapAttrsToList (
          name: profile:
          lib.optionals (profile.bundles != null || profile.patchReload != null) [
            {
              path = "profiles/${name}/package.json";
              text = builtins.toJSON (render.mkProfileManifest name profile);
            }
          ]
          ++ lib.optionals (profile.patches != [ ]) [
            {
              path = "profiles/${name}/cordis.patch.yml";
              text = render.mkProfilePatch profile;
            }
          ]
        ) rt.renderedProfiles
      );

      # (storePath → symlink-name) for every plugin package injected into
      # DSH_HOME/node_modules, mirroring the Home-Manager injection exactly.
      # dir is the parent directory of name under node_modules (e.g.
      # "@deepseek-ai" for scoped packages, "." for unscoped ones).
      nodeModules = map (m: m // { dir = lib.dirOf m.name; }) (
        map (drv: {
          name = drv.dshPluginName;
          target = "${drv}/lib/node_modules/${drv.dshPluginName}";
        }) rt.activePluginDrvs
        ++ lib.optionals (rt.lspEnabled && rt.lspConfiguredServers != { }) [
          {
            name = "@deepseek-ai/dsh-lsp";
            target = "${dshPackage}/lib/dsh/packages/lsp/lsp";
          }
          {
            name = "@deepseek-ai/dsh-lsp-stdio";
            target = "${dshPackage}/lib/dsh/packages/lsp/lsp-stdio";
          }
          {
            name = "@deepseek-ai/dsh-tool-lsp";
            target = "${dshPackage}/lib/dsh/packages/lsp/tool-lsp";
          }
        ]
      );
    in
    pkgs.runCommand "dsh-runtime-seed" { } (
      # Write each text document as its own writeText store file (no shell
      # heredocs — the patch/settings JSONs can contain arbitrary bytes, and
      # quoting them as shell heredocs is fragile), then install the tree and
      # the node_modules plugin symlinks under $out. All lines are joined by a
      # single \n (raw concatenation between groups would merge adjacent
      # lines).
      let
        docFiles = map (d: {
          inherit (d) path;
          drv = pkgs.writeText ("dsh-seed-" + (builtins.replaceStrings [ "/" ] [ "-" ] d.path)) d.text;
        }) textDocs;
      in
      lib.concatStringsSep "\n" (
        [
          "mkdir -p \"$out/profiles\" \"$out/node_modules\""
        ]
        ++ map (d: "cp '${d.drv}' \"\$out/${d.path}\"") docFiles
        ++ map (m: "mkdir -p \"\$out/node_modules/${m.dir}\"") nodeModules
        ++ map (m: "ln -s \"${m.target}\" \"\$out/node_modules/${m.name}\"") nodeModules
      )
    );
in
{
  inherit mkDshRuntime mkDshRuntimeSeed;
}
