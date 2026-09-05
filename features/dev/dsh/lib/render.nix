# features/dev/dsh/lib/render.nix — Pure renderers for the dsh configuration surfaces.
#
# Single source of truth for the option → document mapping across dsh's three
# declarative surfaces:
#   - settings.yaml        — user settings namespaces (`llm-deepseek`, `llm-pi-ai`,
#                            `agent-default-model`)
#   - cordis.patch.yml     — Cordis tree composition (plugin entries)
#   - package.json         — profile manifest (`dsh.profile`)
#   - .credentials.yaml    — dsh credential store records (sops-managed)
# All documents are emitted via `builtins.toJSON`; JSON is a strict subset of
# YAML and accepted by dsh's YAML parser. Upstream schema defaults are never
# rendered — sections only carry genuine overrides.
{
  lib,
}:
let
  # Upstream default of dsh-llm-deepseek's `apiKeyEnv` (config catalog).
  deepseekDefaultApiKeyEnv = "DEEPSEEK_API_KEY";

  # Drop null values: omitted fields inherit the upstream schema default.
  optionalFields = fields: lib.filterAttrs (_: value: value != null) fields;

  # One Cordis plugin entry: stable id, module specifier, composition config.
  mkEntry = id: name: config: {
    inherit id name config;
  };

  # Settings namespace for `@deepseek-ai/dsh-llm-deepseek`; null when dormant
  # (no field deviates from the upstream default).
  mkDeepseekSection =
    deepseek:
    let
      section = optionalFields {
        apiKeyEnv = if deepseek.apiKeyEnv != deepseekDefaultApiKeyEnv then deepseek.apiKeyEnv else null;
        baseURL = deepseek.baseURL;
        thinking = if deepseek.thinking != "enabled" then deepseek.thinking else null;
        reasoningEffort = if deepseek.reasoningEffort != "high" then deepseek.reasoningEffort else null;
        maxTokens = deepseek.maxTokens;
        contextWindow = deepseek.contextWindow;
      };
    in
    if section == { } then null else section;

  # One pi-ai model profile; only non-default fields are rendered.
  mkPiAiModel =
    model:
    optionalFields {
      inherit (model) id;
      name = model.name;
      contextWindow = model.contextWindow;
      maxTokens = model.maxTokens;
      input = if model.input == [ ] then null else model.input;
      reasoningEfforts = if model.reasoningEfforts == { } then null else model.reasoningEfforts;
    };

  # One pi-ai provider route; null when the route is entirely unset.
  mkPiAiProvider =
    provider:
    optionalFields {
      displayName = provider.displayName;
      apiKeyEnv = provider.apiKeyEnv;
      api = provider.api;
      baseURL = provider.baseURL;
      models = if provider.models == [ ] then null else map mkPiAiModel provider.models;
      compat = if provider.compat == { } then null else provider.compat;
      defaultContextWindow = provider.defaultContextWindow;
      defaultMaxTokens = provider.defaultMaxTokens;
      defaultInput = provider.defaultInput;
      retryPolicy = if provider.retryPolicy == { } then null else provider.retryPolicy;
    };

  # Settings namespace for `@deepseek-ai/dsh-llm-pi-ai`; null when dormant.
  mkPiAiSection =
    piAi:
    let
      providers = lib.filterAttrs (_: provider: provider != { }) (
        lib.mapAttrs (_: mkPiAiProvider) piAi.providers
      );
    in
    if providers == { } then null else { inherit providers; };

  # The settings namespaces dsh ships adapters for, keyed as dsh expects.
  # `agent-default-model` is dsh-agent-default-model's settings namespace
  # (provider, model, reasoningEffort?) — the default model belongs in the
  # settings document, NOT in the patch layer: the dsh-base bundle already
  # inserts an `agent-default-model` composition row, and a second insert
  # with the same id fails the boot (duplicate loader entry id).
  mkBaseSettings =
    cfg:
    optionalFields {
      "llm-deepseek" = mkDeepseekSection cfg.deepseek;
      "llm-pi-ai" = mkPiAiSection cfg.piAi;
      "agent-default-model" =
        if cfg.defaultModel == null then
          null
        else
          {
            inherit (cfg.defaultModel) provider model;
          };
    };

  # Credential store document (`$DSH_HOME/.credentials.yaml`), version 1.
  # The `refs` section is the flat CredentialRef-to-secret mapping the
  # credentials service resolves per request (POSIX env-name keys); the
  # `records` section (`<scope>/<id>` sign-in data) is left to the Models
  # page and never rendered here.
  mkCredentialsDoc = credentials: {
    version = 1;
    refs = lib.mapAttrs (_: record: record.key) credentials;
  };

  # One stdio/Streamable-HTTP MCP server entry for `@deepseek-ai/dsh-mcp-client`.
  mkMcpEntry =
    name: server:
    mkEntry "mcp-${name}" "@deepseek-ai/dsh-mcp-client" (
      optionalFields (
        {
          serverName = name;
          transport = server.transport;
          toolCallTimeoutMs = server.toolCallTimeoutMs;
          failOnStartupError = if server.failOnStartupError then server.failOnStartupError else null;
        }
        // (lib.optionalAttrs (server.transport == "stdio") {
          command =
            if server.command != null then
              server.command
            else if server.package != null && server.binName != null then
              "${server.package}/bin/${server.binName}"
            else
              null;
          args = if server.args == [ ] then null else server.args;
          env = if server.env == { } then null else server.env;
          inherit (server) cwd;
        })
        // (lib.optionalAttrs (server.transport == "streamable-http") {
          inherit (server) url;
          headers = if server.headers == { } then null else server.headers;
        })
      )
    );

  # One persona entry for `@deepseek-ai/dsh-persona`.
  mkPersonaEntry =
    persona:
    mkEntry "persona" "@deepseek-ai/dsh-persona" (
      if lib.isString persona then
        { text = persona; }
      else
        optionalFields {
          inherit (persona) text;
          complete = if persona.complete then persona.complete else null;
          includeRuntimeContext = persona.includeRuntimeContext;
        }
    );

  # The home-level Cordis patch layer (`$DSH_HOME/cordis.patch.yml`) composing
  # every machine-wide entry: MCP servers, persona, plugin bundles. The
  # default model is a settings namespace (see mkBaseSettings), not a patch
  # row — the dsh-base bundle owns the `agent-default-model` row.
  mkHomePatch = entries: if entries == [ ] then null else builtins.toJSON [ { insert = entries; } ];

  # One bundle row for an injected plugin: bare-name resolution from the
  # installation's node_modules; the row id equals the package name.
  mkPluginEntry = name: config: mkEntry name name config;

  mkHomePatchEntries =
    {
      mcpServers,
      persona,
      pluginConfigs ? { },
      pluginBundleNames,
    }:
    lib.optionals (mcpServers != { }) (lib.mapAttrsToList mkMcpEntry mcpServers)
    ++ lib.optional (persona != null) (mkPersonaEntry persona)
    ++ map (name: mkPluginEntry name (pluginConfigs.${name} or { })) pluginBundleNames;

  # A profile manifest (`package.json` beside the profile patch layer). Called
  # only for profiles with bundles or patchReload configured (the upstream
  # profile template applies untouched otherwise).
  mkProfileManifest = name: profile: {
    name = "dsh-profile-${name}";
    dsh = {
      profile = optionalFields {
        bundles = profile.bundles;
        patchReload = profile.patchReload;
      };
    };
  };

  # A profile's own patch layer; call only for profiles declaring patches.
  mkProfilePatch = profile: builtins.toJSON profile.patches;
in
{
  inherit
    optionalFields
    mkDeepseekSection
    mkPiAiSection
    mkBaseSettings
    mkCredentialsDoc
    mkMcpEntry
    mkPersonaEntry
    mkPluginEntry
    mkHomePatch
    mkHomePatchEntries
    mkProfileManifest
    mkProfilePatch
    ;
}
