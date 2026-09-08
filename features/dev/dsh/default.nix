# features/dev/dsh/default.nix — Generic DeepSeek Harness (dsh) feature module.
#
# Architecture & Guidelines:
# - Pure SYSTEM module: dsh runs as a persistent systemd SYSTEM service as a
#   dedicated, unprivileged `dsh` system user with DSH_HOME=/var/lib/dsh (MTAA
#   multi-tenant store root) on every host. There is no Home-Manager per-user
#   ~/.dsh materialization; the configuration documents are rendered by
#   mkDshRuntimeSeed into /var/lib/dsh by the dsh-web-config oneshot unit.
# - Model adapter options, credential records (sops), MCP servers, personas,
#   and the machine-wide Cordis patch layer are all system-level.
# - Agnostic & Generic: Zero hardcoded usernames, hostnames, or stacks.
# - Declarative posture: settings.yaml and the Cordis patch layer are rendered
#   from Nix options (JSON ⊂ YAML); dsh's hot reload reads them untouched.
# - Secrets never enter settings — only credential references (apiKeyEnv);
#   values live in the sops-managed .credentials.yaml (mode 0600, dsh refuses
#   group/other-readable credential files).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.dev.dsh;
  render = import ./lib/render.nix { inherit lib; };
  pluginsLib = import ./lib/plugins.nix { inherit lib pkgs; };
  runtime = import ./lib/runtime.nix {
    inherit
      lib
      render
      pluginsLib
      pkgs
      ;
  };

  # The dsh-web SYSTEM service's runtime identity. It runs as the dedicated,
  # unprivileged multi-tenant user with DSH_HOME=/var/lib/dsh (MTAA store root).
  serviceUser = cfg.web.dedicatedUserName;
  serviceDshHome = "/var/lib/dsh";

  # Owner of the sops-rendered credential/OIDC documents. These MUST be readable
  # by the process that reads them — the dsh-web SYSTEM service's User — because
  # dsh refuses group/other-readable credential files (0600 + owner).
  credOwner = serviceUser;

  mcpServerAssertions = lib.flatten (
    lib.mapAttrsToList (name: server: [
      {
        assertion =
          server.transport == "stdio"
          -> server.command != null || (server.package != null && server.binName != null);
        message = "my.features.dev.dsh.mcpServers.${name}: stdio transport requires (package + binName) or command.";
      }
      {
        assertion = server.transport == "streamable-http" -> server.url != null;
        message = "my.features.dev.dsh.mcpServers.${name}: streamable-http transport requires url.";
      }
    ]) cfg.mcpServers
  );
in
{
  imports = [ pluginsLib.optionsModule ];

  options.my.features.dev.dsh = {
    enable = lib.mkEnableOption "system-wide dsh credential records and configuration";

    package = lib.mkPackageOption pkgs [
      "custom"
      "dsh"
    ] { };

    web = {
      enable = lib.mkEnableOption "background dsh web server daemon";
      port = lib.mkOption {
        type = lib.types.port;
        default = 3080;
        description = "Port for the dsh web server.";
      };
      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Host/IP address for the dsh web server to bind to.";
      };
      dedicatedUserName = lib.mkOption {
        type = lib.types.str;
        default = "dsh";
        description = "Username of the dedicated dsh system user (group of the same name), with home /var/lib/dsh.";
      };
    };

    deepseek = lib.mkOption {
      type = lib.types.submodule {
        options = {
          apiKeyEnv = lib.mkOption {
            type = lib.types.str;
            default = "DEEPSEEK_API_KEY";
            description = "Credential reference (environment-variable name) resolved per request.";
          };
          baseURL = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Endpoint base; defaults to $DEEPSEEK_BASE_URL, then the public API.";
          };
          thinking = lib.mkOption {
            type = lib.types.enum [
              "enabled"
              "disabled"
            ];
            default = "enabled";
            description = "Deployment thinking policy; disabled limits every request to off.";
          };
          reasoningEffort = lib.mkOption {
            type = lib.types.enum [
              "off"
              "low"
              "high"
              "max"
            ];
            default = "high";
            description = "Default thinking effort; off disables thinking per request.";
          };
          maxTokens = lib.mkOption {
            type = lib.types.nullOr lib.types.int;
            default = null;
            description = "Default per-request output cap (upstream default 256000).";
          };
          contextWindow = lib.mkOption {
            type = lib.types.nullOr lib.types.int;
            default = null;
            description = "Positive context capacity fallback (upstream default 1000000).";
          };
        };
      };
      default = { };
      description = "Settings namespace for the direct DeepSeek adapter (llm-deepseek).";
    };

    piAi = lib.mkOption {
      type = lib.types.submodule {
        options = {
          providers = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  displayName = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "Label shown by model selector surfaces.";
                  };
                  apiKeyEnv = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "Credential reference; omission defers to ambient discovery.";
                  };
                  api = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "Wire protocol; only needed for routes the catalog does not ship.";
                  };
                  baseURL = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "Endpoint for this route's models.";
                  };
                  models = lib.mkOption {
                    type = lib.types.listOf (
                      lib.types.submodule {
                        options = {
                          id = lib.mkOption {
                            type = lib.types.str;
                            description = "Provider-owned model id.";
                          };
                          name = lib.mkOption {
                            type = lib.types.nullOr lib.types.str;
                            default = null;
                            description = "Display name.";
                          };
                          contextWindow = lib.mkOption {
                            type = lib.types.nullOr lib.types.int;
                            default = null;
                            description = "Context capacity.";
                          };
                          maxTokens = lib.mkOption {
                            type = lib.types.nullOr lib.types.int;
                            default = null;
                            description = "Output cap.";
                          };
                          input = lib.mkOption {
                            type = lib.types.listOf (
                              lib.types.enum [
                                "text"
                                "image"
                              ]
                            );
                            default = [ ];
                            description = "Modalities; hand-entered models are text-only until declared.";
                          };
                          reasoningEfforts = lib.mkOption {
                            type = lib.types.attrsOf lib.types.anything;
                            default = { };
                            description = "Declared reasoning levels (effort → wire value).";
                          };
                        };
                      }
                    );
                    default = [ ];
                    description = "Replaces the route's installed catalog wholesale.";
                  };
                  compat = lib.mkOption {
                    type = lib.types.attrsOf lib.types.anything;
                    default = { };
                    description = "Wire-compatibility switches for unrecognized endpoints.";
                  };
                  defaultContextWindow = lib.mkOption {
                    type = lib.types.nullOr lib.types.int;
                    default = null;
                    description = "Capacity fallback for undescribed models (upstream default 262144).";
                  };
                  defaultInput = lib.mkOption {
                    type = lib.types.nullOr (
                      lib.types.listOf (
                        lib.types.enum [
                          "text"
                          "image"
                        ]
                      )
                    );
                    default = null;
                    description = "Fallback modalities for models the catalog does not describe (e.g. [text image]).";
                  };
                  defaultMaxTokens = lib.mkOption {
                    type = lib.types.nullOr lib.types.int;
                    default = null;
                    description = "Output-cap fallback for undescribed models (upstream default 32768).";
                  };
                  retryPolicy = lib.mkOption {
                    type = lib.types.attrsOf lib.types.anything;
                    default = { };
                    description = "Provider-owned retry policy (mode, maxRetries).";
                  };
                };
              }
            );
            default = { };
            description = "pi-ai provider routes keyed by provider.";
          };
        };
      };
      default = { };
      description = "Settings namespace for the multi-provider pi-ai adapter (llm-pi-ai).";
    };

    defaultModel = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.submodule {
          options = {
            provider = lib.mkOption {
              type = lib.types.str;
              description = "Registered provider route.";
            };
            model = lib.mkOption {
              type = lib.types.str;
              description = "Provider-owned model id.";
            };
          };
        }
      );
      default = null;
      description = "Default model selection, rendered into the agent-default-model settings namespace.";
    };

    persona = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.either lib.types.str (
          lib.types.submodule {
            options = {
              text = lib.mkOption {
                type = lib.types.str;
                description = "Persona prose rendered as the deployment:persona prompt section.";
              };
              complete = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Make this persona the complete system prompt.";
              };
              includeRuntimeContext = lib.mkOption {
                type = lib.types.nullOr lib.types.bool;
                default = null;
                description = "Suppress dynamic runtime-context snapshots for this persona's agent scope.";
              };
            };
          }
        )
      );
      default = null;
      description = "Deployment persona (dsh-persona patch entry); string shorthand for { text }.";
    };

    mcpServers = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            transport = lib.mkOption {
              type = lib.types.enum [
                "stdio"
                "streamable-http"
              ];
              default = "stdio";
              description = "MCP transport of this server.";
            };
            package = lib.mkOption {
              type = lib.types.nullOr lib.types.package;
              default = null;
              description = "MCP server package (added to the user profile for closure).";
            };
            binName = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Executable name under the package's bin/ directory.";
            };
            command = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Explicit executable, overriding package + binName.";
            };
            args = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Arguments passed directly, without shell interpolation.";
            };
            env = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              description = "Extra environment variables merged on top of the scrubbed ambient env.";
            };
            cwd = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Working directory for the child process.";
            };
            url = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "MCP endpoint URL (streamable-http).";
            };
            headers = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              description = "Additional headers attached to MCP requests (streamable-http).";
            };
            toolCallTimeoutMs = lib.mkOption {
              type = lib.types.nullOr lib.types.int;
              default = null;
              description = "Per-tool-call timeout in milliseconds.";
            };
            failOnStartupError = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Fail plugin activation when the initial connection fails.";
            };
          };
        }
      );
      default = { };
      description = "MCP servers (dsh-mcp-client entries) in the machine-wide Cordis patch layer.";
    };

    profiles = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            bundles = lib.mkOption {
              type = lib.types.nullOr (lib.types.listOf lib.types.str);
              default = null;
              description = "Ordered bundle layer list; null keeps the upstream profile template.";
            };
            patchReload = lib.mkOption {
              type = lib.types.nullOr (
                lib.types.enum [
                  "startup"
                  "live"
                ]
              );
              default = null;
              description = "User patch-file lifecycle; null keeps the upstream template default.";
            };
            patches = lib.mkOption {
              type = lib.types.listOf lib.types.anything;
              default = [ ];
              description = "This profile's own Cordis patch entries, applied after every bundle layer.";
            };
          };
        }
      );
      default = { };
      description = "Declaratively managed profiles under $DSH_HOME/profiles/<name>.";
    };

    credentials = lib.mkOption {
      # Submodule shape (matching the proven pi pattern): a plain attrsOf str
      # would type-check its values eagerly during the module merge, forcing
      # config.sops.placeholder while sops.placeholder itself is gated on
      # sops.templates != { } — an eval cycle. Submodule option checks stay
      # lazy, breaking the loop.
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            key = lib.mkOption {
              type = lib.types.str;
              description = "Key value, typically from config.sops.placeholder.";
            };
          };
        }
      );
      default = { };
      description = "Credential refs keyed by credential reference (POSIX env name, e.g. DEEPSEEK_API_KEY), rendered into the version-1 refs section of the sops-managed .credentials.yaml.";
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Host-wide settings.yaml override (merged above rendered namespaces).";
    };

    auth = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable the unified @dsh/auth gateway plugin.";
      };

      mode = lib.mkOption {
        type = lib.types.enum [
          "auto"
          "forward-proxy"
          "oidc"
          "ldap"
          "loopback-only"
        ];
        default = "auto";
        description = "Primary authentication mode.";
      };

      forwardProxy = {
        enabled = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Trust identity headers from upstream reverse proxy (e.g. Authentik/Caddy).";
        };
        trustedProxies = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "127.0.0.1"
            "::1"
          ];
          description = "IP addresses of trusted reverse proxies.";
        };
        adminGroups = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "authentik Admins"
            "wheel"
            "admin"
          ];
          description = "Proxy group names mapped to Admin clearance.";
        };
        memberGroups = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "family"
            "users"
            "member"
          ];
          description = "Proxy group names mapped to Member clearance.";
        };
      };

      oidc = {
        enabled = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Direct OIDC identity provider integration (interactive Authorization Code + PKCE).";
        };
        issuer = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "OIDC issuer discovery URL (e.g. https://auth.ancoris.ovh/application/o/dsh/).";
        };
        clientId = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "OIDC client ID.";
        };
        clientSecret = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "OIDC client secret (prefer clientSecretEnv/credential over plaintext).";
        };
        clientSecretEnv = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Env/credential ref holding the OIDC client secret (avoids plaintext in config).";
        };
        scopes = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "openid"
            "profile"
            "email"
          ];
          description = "OIDC scopes requested at authorize.";
        };
        redirectUri = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "https://dsh.mky.ancoris.ovh/oidc/callback";
          description = "Callback URI this dsh-web instance expects (defaults to http://127.0.0.1:3080/oidc/callback).";
        };
        logoutUri = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Authentik end_session endpoint (optional).";
        };
        adminClaim = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "OIDC claim carrying the user's groups (default 'groups').";
        };
        adminValues = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "admin" ];
          description = "Group values mapped to Admin clearance.";
        };
      };

      ldap = {
        enabled = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Direct LDAP directory integration.";
        };
        url = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "LDAP server URL (e.g. ldaps://ldap.ancoris.ovh:636).";
        };
        baseDn = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Base DN for user search.";
        };
      };

      loopback = {
        enabled = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Allow seamless local loopback access (127.0.0.1).";
        };
      };

      peerMesh = {
        enabled = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "HMAC cluster authentication for peer-to-peer node mesh.";
        };
        clusterSecret = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Shared secret for HMAC-SHA256 inter-node authentication.";
        };
      };
    };

    mesh = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable distributed cluster mesh fabric.";
      };
      listenPort = lib.mkOption {
        type = lib.types.port;
        default = 3891;
        description = "TCP port for distributed cluster mesh heartbeat and gossip.";
      };
      peers = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              id = lib.mkOption {
                type = lib.types.str;
                description = "Cluster peer node identifier.";
              };
              endpoint = lib.mkOption {
                type = lib.types.str;
                description = "Peer endpoint (host:port or URL).";
              };
              tags = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Node tags/capabilities (e.g. server, gpu).";
              };
            };
          }
        );
        default = [ ];
        description = "System-wide cluster peer nodes declaratively provisioned via Nix.";
      };
      groupPeers = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.listOf (
            lib.types.submodule {
              options = {
                id = lib.mkOption {
                  type = lib.types.str;
                  description = "Cluster peer node identifier.";
                };
                endpoint = lib.mkOption {
                  type = lib.types.str;
                  description = "Peer endpoint (host:port or URL).";
                };
                tags = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                  description = "Node tags/capabilities (e.g. server, gpu, team).";
                };
              };
            }
          )
        );
        default = { };
        description = "Group-restricted cluster peer nodes provisioned per group (e.g. dev, family).";
      };
    };

    memory = {
      facts = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              subject = lib.mkOption {
                type = lib.types.str;
                description = "Subject entity URI.";
              };
              predicate = lib.mkOption {
                type = lib.types.str;
                description = "Predicate relation.";
              };
              object = lib.mkOption {
                type = lib.types.str;
                description = "Target entity URI or literal value.";
              };
              type_constraint = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = "String";
                description = "Type constraint (e.g. String, Port, IPv4, FQDN).";
              };
              confidence = lib.mkOption {
                type = lib.types.float;
                default = 1.0;
                description = "Confidence value between 0.0 and 1.0.";
              };
              security_label = lib.mkOption {
                type = lib.types.enum [
                  "system"
                  "operator"
                  "user"
                ];
                default = "system";
                description = "Lattice security clearance required.";
              };
              scope_type = lib.mkOption {
                type = lib.types.enum [
                  "public"
                  "group"
                  "user"
                  "repo"
                ];
                default = "public";
                description = "Memory scope type.";
              };
              scope_id = lib.mkOption {
                type = lib.types.str;
                default = "public";
                description = "Memory scope target ID (e.g. public, group:dev, repo:nixfiles).";
              };
            };
          }
        );
        default = [ ];
        description = "System-wide declarative invariant facts provisioned via Nix.";
      };
      maxRecallTokens = lib.mkOption {
        type = lib.types.int;
        default = 150;
        description = "Hard token cap for memory context injected into the prompt.";
      };
      minRecallThreshold = lib.mkOption {
        type = lib.types.float;
        default = -1.5;
        description = "Minimum BM25 score threshold (FTS5 rank cutoff; more negative = stronger match).";
      };
      embedding = {
        enable = lib.mkEnableOption "local vector embeddings (cosine recall) in dsh-memory" // {
          default = false;
          description = "When enabled, facts get embedded and the recall cascade adds a cosine stage.";
        };
        provider = lib.mkOption {
          type = lib.types.enum [
            "feature-hash"
            "api"
            "onnx"
          ];
          default = "feature-hash";
          description = "Embedding backend. 'feature-hash' local/deterministic baseline; 'api' OpenAI-compatible endpoint (agnostic/scalable); 'onnx' bundled neural model.";
        };
        dim = lib.mkOption {
          type = lib.types.int;
          default = 512;
          description = "Dimensionality (feature-hash baseline; api dims; onnx uses the model dims unless overridden).";
        };
        minSimilarity = lib.mkOption {
          type = lib.types.float;
          default = 0.0;
          description = "Cosine floor; candidates below this are discarded by the vector stage. For api/onnx the plugin defaults to 0.5 unless set.";
        };
        similarityMargin = lib.mkOption {
          type = lib.types.float;
          default = 0.2;
          description = "Relative margin to the best cosine; facts further from the top result than this are trimmed (adaptive relevance cut).";
        };
        topK = lib.mkOption {
          type = lib.types.int;
          default = 8;
          description = "Number of vector candidates considered per recall.";
        };
        weight = lib.mkOption {
          type = lib.types.float;
          default = 0.7;
          description = "Blend weight (0..1) of cosine vs BM25 in the fused recall score; embedding is primary.";
        };
        entropyMinStems = lib.mkOption {
          type = lib.types.int;
          default = 1;
          description = "Minimum substantive stems for a query to trigger recall (1 allows single-entity queries).";
        };
        batchSize = lib.mkOption {
          type = lib.types.int;
          default = 16;
          description = "Max inputs per batched embedding request (api).";
        };
        apiBase = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "OpenAI-compatible base URL for /v1/embeddings (api; defaults to OpenRouter).";
        };
        apiModel = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Embedding model identifier (api; defaults to openai/text-embedding-3-small).";
        };
        apiKeyEnv = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Environment variable holding the embedding API key (api; defaults to OPENROUTER_API_KEY).";
        };
        modelDir = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Override the ONNX model+tokenizer directory (defaults to the plugin-bundled onnx/).";
        };
        modelId = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Override the transformers.js model identifier (defaults to the bundled local model dir).";
        };
      };
      replication = {
        enable = lib.mkEnableOption "cross-node memory replication (C7) in dsh-memory" // {
          default = false;
          description = "Capability-token-signed delta sync (union-CRDT + OR-Set tombstones, HLC-ordered) of public/group/user facts across peer nodes. Fail-closed: without a resolvable secret, replication silently stays off.";
        };
        nodeId = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Local nodeId used as this node's origin identifier (defaults to DSH_NODE_ID or 'standalone').";
        };
        tenantContext = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "group:dev";
          description = "Tenant replication context: 'user:<u>' or 'group:<g>'. Replication never crosses this boundary (MTAA isolation). Defaults to 'user:local'.";
        };
        scopes = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "public" ];
          example = [
            "public"
            "group:dev"
            "user:philipp"
          ];
          description = "Scopes this node is willing to replicate (public, group:<g>, user:<u>). Peers are derived agnostically from presence + OIDC (no hand-list); only these scopes are ever shared.";
        };
        secretEnv = lib.mkOption {
          type = lib.types.str;
          default = "DSH_MEMORY_HMAC";
          description = "Credential/env reference holding the shared secret for capability signing + body HMAC (resolved via the dsh credential store, never in settings).";
        };
        listenPort = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
          description = "Bind a local HTTP endpoint so peers can pull from this node. Null disables serving.";
        };
        listenHost = lib.mkOption {
          type = lib.types.str;
          default = "0.0.0.0";
          description = "Bind address for the serving HTTP endpoint.";
        };
        syncIntervalMs = lib.mkOption {
          type = lib.types.int;
          default = 30000;
          description = "Pull cadence in ms (0/negative run sync only once at startup).";
        };
        maxVersionsPerSync = lib.mkOption {
          type = lib.types.int;
          default = 512;
          description = "Max versions per delta response (pagination).";
        };
        peers = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                nodeId = lib.mkOption {
                  type = lib.types.str;
                  description = "Remote peer nodeId.";
                };
                endpoint = lib.mkOption {
                  type = lib.types.str;
                  description = "Peer endpoint (host:port or http URL) where /mesh/memory/sync is served.";
                };
                direction = lib.mkOption {
                  type = lib.types.enum [
                    "pull"
                    "push"
                    "bidirectional"
                  ];
                  default = "bidirectional";
                  description = "Sync direction for this peer.";
                };
                scopes = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ "public" ];
                  example = [
                    "public"
                    "group:dev"
                  ];
                  description = "Scope ids to replicate (public, group:<g>, user:<u>). repo:* is never replicated by default.";
                };
              };
            }
          );
          default = [ ];
          description = "Peers to pull from / serve to.";
        };
      };
      decay = {
        enable = lib.mkEnableOption "derived confidence decay (A1) in dsh-memory" // {
          default = false;
          description = "Effective confidence decays exponentially with age for evidence/hypothesis (Axioms never decay). Derived, never stored — stays convergent across nodes.";
        };
        halfLifeSeconds = lib.mkOption {
          type = lib.types.int;
          default = 7776000;
          description = "Half-life in seconds (default 90 days). 0 disables decay.";
        };
        floor = lib.mkOption {
          type = lib.types.float;
          default = 0.15;
          description = "Below this derived confidence a fact is dropped from recall. -1 disables the filter.";
        };
        retentionSeconds = lib.mkOption {
          type = lib.types.int;
          default = 0;
          description = "Physical pruning: retain retracted/historical versions for this many seconds before deletion (0 = keep all history). Peer-cursor-safe (never prunes below a peer cursor).";
        };
        vacuumIntervalSeconds = lib.mkOption {
          type = lib.types.int;
          default = 0;
          description = "Run the physical compaction (VACUUM) every this many seconds (0 = disabled).";
        };
      };
    };

    lsp = {
      enable = lib.mkEnableOption "declarative LSP code intelligence in dsh" // {
        default = true;
      };
      maxLocations = lib.mkOption {
        type = lib.types.int;
        default = 100;
        description = "Largest number of rendered locations before an omission marker.";
      };
      maxResultChars = lib.mkOption {
        type = lib.types.int;
        default = 16000;
        description = "Largest complete rendered result in characters, including truncation metadata.";
      };
      timeoutMs = lib.mkOption {
        type = lib.types.int;
        default = 60000;
        description = "Tool-call timeout budget in milliseconds covering the queued open/query/close lifecycle.";
      };
      servers = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              enable = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Whether this language server is enabled.";
              };
              package = lib.mkOption {
                type = lib.types.nullOr lib.types.package;
                default = null;
                description = "Nix package providing the language server binary.";
              };
              command = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Explicit executable path, overriding package binary lookup.";
              };
              args = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Command-line arguments passed to the language server.";
              };
              extensionToLanguage = lib.mkOption {
                type = lib.types.attrsOf lib.types.str;
                description = "Lowercase leading-dot extension to LSP language ID mapping (e.g. { \".nix\" = \"nix\"; }).";
              };
              env = lib.mkOption {
                type = lib.types.attrsOf lib.types.str;
                default = { };
                description = "Extra environment variables merged into the server process.";
              };
              initializationOptions = lib.mkOption {
                type = lib.types.nullOr lib.types.anything;
                default = null;
                description = "Static initialization options forwarded to the server.";
              };
              configuration = lib.mkOption {
                type = lib.types.nullOr lib.types.anything;
                default = null;
                description = "Static answer to workspace/configuration items.";
              };
              maxMessageBytes = lib.mkOption {
                type = lib.types.nullOr lib.types.int;
                default = null;
                description = "Largest single framed message accepted from the server in bytes (default 16MB).";
              };
              maxStderrBytes = lib.mkOption {
                type = lib.types.nullOr lib.types.int;
                default = null;
                description = "Largest stderr tail retained for diagnostics in bytes (default 1MB).";
              };
              maxDocumentBytes = lib.mkOption {
                type = lib.types.nullOr lib.types.int;
                default = null;
                description = "Largest source file this host will open in bytes (default 4MB).";
              };
              shutdownTimeoutMs = lib.mkOption {
                type = lib.types.nullOr lib.types.int;
                default = null;
                description = "Graceful shutdown/exit budget before escalation in ms (default 5000).";
              };
              killGraceMs = lib.mkOption {
                type = lib.types.nullOr lib.types.int;
                default = null;
                description = "Request-cancel and SIGTERM to SIGKILL grace in ms (default 2000).";
              };
            };
          }
        );
        default = { };
        description = "Configured stdio language servers registered on ctx.lsp.";
      };
    };
  };

  config = lib.mkMerge [
    {
      my.features.dev.dsh.mcpServers = lib.mkDefault (
        {
          nixos = {
            package = pkgs.mcp-nixos;
            binName = "mcp-nixos";
          };
        }
        // lib.optionalAttrs (config.my.role != "server") {
          chrome-devtools = {
            package = pkgs.custom.chrome-devtools-mcp;
            binName = "chrome-devtools-mcp";
            args = [
              "--executablePath"
              "${pkgs.google-chrome}/bin/google-chrome-stable"
            ];
          };
        }
      );

      my.features.dev.dsh.lsp.servers = lib.mkDefault {
        nil = {
          package = pkgs.nil;
          extensionToLanguage = {
            ".nix" = "nix";
          };
        };
        typescript = {
          package = pkgs.typescript-language-server;
          args = [ "--stdio" ];
          extensionToLanguage = {
            ".ts" = "typescript";
            ".tsx" = "typescriptreact";
            ".js" = "javascript";
            ".jsx" = "javascriptreact";
            ".mjs" = "javascript";
            ".cjs" = "javascript";
          };
        };
        csharp = {
          package = pkgs.csharp-ls;
          extensionToLanguage = {
            ".cs" = "csharp";
          };
        };
      };
    }

    {
      assertions = mcpServerAssertions;
    }

    (lib.mkIf (cfg.enable || cfg.credentials != { } || cfg.auth.oidc.enabled) {
      sops.templates."dsh-credentials.yaml" = lib.mkIf (cfg.credentials != { }) {
        owner = credOwner;
        # dsh refuses credential files readable by group or others.
        mode = "0600";
        content = builtins.toJSON (render.mkCredentialsDoc cfg.credentials);
      };

      # OIDC client secret for the dsh-web process (never in the flake).
      sops.secrets."dsh_oidc_client_secret" = lib.mkIf (cfg.auth.oidc.enabled) {
        owner = credOwner;
        mode = "0600";
      };
      sops.templates."dsh-oidc.env" = lib.mkIf (cfg.auth.oidc.enabled) {
        owner = credOwner;
        mode = "0600";
        content = ''
          DHS_OIDC_CLIENT_SECRET=${config.sops.placeholder."dsh_oidc_client_secret"}
        '';
      };

      systemd.tmpfiles.rules =
        let
          normalUsers = lib.filterAttrs (_: u: u.isNormalUser) config.users.users;
          # The /var/lib/dsh store root belongs to the dedicated dsh service user.
          dshUser = cfg.web.dedicatedUserName;
          tenantDirs = lib.mapAttrsToList (
            name: _: "d /var/lib/dsh/tenants/${name} 0700 ${name} users -"
          ) normalUsers;
        in
        [
          "d /var/lib/dsh 0755 ${dshUser} ${dshUser} -"
          "d /var/lib/dsh/tenants 0755 ${dshUser} ${dshUser} -"
          "d /var/lib/dsh/shared 0755 ${dshUser} ${dshUser} -"
          "d /run/dsh 0775 root users -"
        ]
        ++ tenantDirs;

      # Instantly release distributed session leases when suspending/sleeping
      powerManagement.powerDownCommands = ''
        ${pkgs.procps}/bin/pkill -SIGUSR1 -f "dsh" || true
      '';
    })

    # MTAA: dedicated unprivileged `dsh` system user whose home IS the
    # multi-tenant store root /var/lib/dsh. The dsh-web SYSTEM service runs as
    # this user; operator + tenant data all lives under /var/lib/dsh.
    {
      users.groups.${cfg.web.dedicatedUserName} = { };

      users.users.${cfg.web.dedicatedUserName} = {
        isSystemUser = true;
        group = cfg.web.dedicatedUserName;
        home = "/var/lib/dsh";
        createHome = true;
        description = "DeepSeek Harness (dsh) multi-tenant system user";
      };

      # Config-document seed for /var/lib/dsh, rendered from the same
      # mkDshRuntime documents the dsh-web system service reads. Installed as
      # the dsh user before the dsh-web service starts.
      systemd.services.dsh-web-config = {
        description = "Populate /var/lib/dsh with the dsh configuration documents";
        wantedBy = [ "multi-user.target" ];
        before = [ "dsh-web.service" ];
        after = [ "network.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "root";
        };
        script =
          let
            seed = runtime.mkDshRuntimeSeed {
              # Match the system runtime: no user-specific settings/facts/peers.
              systemCfg = cfg;
              osConfig = config;
              userCfg = { };
              currentUser = null;
            };
            dshUser = cfg.web.dedicatedUserName;
            target = "/var/lib/dsh";
          in
          ''
            mkdir -p "${target}"
            # Copy the declarative seed (settings.yaml, cordis.patch.yml,
            # profiles/, node_modules) into /var/lib/dsh, owned by ${dshUser}.
            cp -a "${seed}"/. "${target}"/
            chown -R "${dshUser}:${dshUser}" "${target}"
            chmod -R u+rwX,g-rwx,o-rwx "${target}"
          '';
      };
    }

    # Run dsh-web as a persistent systemd SYSTEM service on the public /
    # multi-tenant node (independent of any user session). The service runs as
    # serviceUser with DSH_HOME=serviceDshHome (/var/lib/dsh when a dedicated
    # MTAA user is configured). The dsh-web-config unit instantiates the
    # configuration documents into DSH_HOME first.
    # Run dsh-web as a persistent systemd SYSTEM service (independent of any
    # user session). It runs as the dedicated dsh user with
    # DSH_HOME=/var/lib/dsh; the dsh-web-config unit instantiates the config
    # documents into the store root first.
    (lib.mkIf cfg.web.enable {
      systemd.services.dsh-web = {
        description = "DeepSeek Harness (dsh) Web UI Service (systemd system service)";
        wantedBy = [ "multi-user.target" ];
        after = [
          "network.target"
          "dsh-web-config.service"
        ];
        requires = [ "dsh-web-config.service" ];
        serviceConfig = {
          Type = "simple";
          User = serviceUser;
          WorkingDirectory = serviceDshHome;
          ExecStart = "${
            if cfg.package or null != null then cfg.package else pkgs.custom.dsh
          }/bin/dsh web --no-open --host ${cfg.web.host} --port ${toString cfg.web.port}";
          Environment = [ "DSH_HOME=${serviceDshHome}" ];
          EnvironmentFile = lib.optionals (config.sops.templates ? "dsh-oidc.env") [
            config.sops.templates."dsh-oidc.env".path
          ];
          Restart = "on-failure";
          RestartSec = "5s";
        };
      };
    })
  ];
}
