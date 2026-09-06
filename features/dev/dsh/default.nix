# features/dev/dsh/default.nix — Generic DeepSeek Harness (dsh) feature module.
#
# Architecture & Guidelines:
# - System Level: model adapter options, credential records (sops), MCP servers,
#   personas, and the machine-wide Cordis patch layer.
# - User-Scoped Level (home-manager.sharedModules): exposes my.features.dev.dsh.enable
#   and materializes the three dsh configuration documents under $DSH_HOME.
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

  activePluginNames = lib.filter (name: (cfg.plugins.${name}.enable or true)) pluginsLib.pluginNames;
  activePluginDrvs = map (name: pluginsLib.derivations.${name}) activePluginNames;
  activePluginBundleNames = map (name: pluginsLib.bundleNameOf name) activePluginNames;

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

    dshHome = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Harness home override; sets DSH_HOME (defaults to ~/.dsh).";
    };

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
          description = "Direct OIDC identity provider integration.";
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
          description = "OIDC client secret.";
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

    (lib.mkIf (cfg.enable || cfg.credentials != { }) {
      sops.templates."dsh-credentials.yaml" = lib.mkIf (cfg.credentials != { }) {
        owner = config.my.user.primary or "root";
        # dsh refuses credential files readable by group or others.
        mode = "0600";
        content = builtins.toJSON (render.mkCredentialsDoc cfg.credentials);
      };

      systemd.tmpfiles.rules =
        let
          normalUsers = lib.filterAttrs (_: u: u.isNormalUser) config.users.users;
          tenantDirs = lib.mapAttrsToList (
            name: _: "d /var/lib/dsh/tenants/${name} 0700 ${name} users -"
          ) normalUsers;
        in
        [
          "d /var/lib/dsh 0755 root root -"
          "d /var/lib/dsh/tenants 0755 root root -"
          "d /var/lib/dsh/shared 0755 root root -"
          "d /run/dsh 0775 root users -"
        ]
        ++ tenantDirs;
    })

    {
      home-manager.sharedModules = [
        (
          {
            config,
            lib,
            pkgs,
            osConfig ? { },
            ...
          }:
          let
            userCfg = config.my.features.dev.dsh;
            systemCfg = osConfig.my.features.dev.dsh or { };

            mcpServers = systemCfg.mcpServers or { };

            baseSettings = render.mkBaseSettings systemCfg;
            settingsDoc = lib.recursiveUpdate (lib.recursiveUpdate baseSettings (
              systemCfg.settings or { }
            )) userCfg.settings;

            topologyHosts = osConfig.my.features.system.networking.topology.hosts or { };
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

            currentHost = osConfig.networking.hostName or "unknown";
            currentUser = osConfig.my.user.name or (builtins.getEnv "USER");

            # Auto-discovered Tailscale topology peers
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

            # System-wide explicitly configured peers
            systemExplicitPeers = map (p: p // { scope = "system"; }) (systemCfg.mesh.peers or [ ]);

            # System-wide group-restricted peers
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

            # User-specific personal peers
            userPersonalPeers = map (
              p:
              p
              // {
                scope = "user";
                owner = currentUser;
              }
            ) (userCfg.mesh.userPeers or [ ]);

            allConfiguredPeers = topologyPeers ++ systemExplicitPeers ++ systemGroupPeers ++ userPersonalPeers;

            authCfg = systemCfg.auth or { };

            # Invariant memory facts: topology facts + system facts + user personal facts
            allConfiguredFacts =
              topologyFacts
              ++ (systemCfg.memory.facts or [ ])
              ++ (map (
                f:
                f
                // {
                  scope_id = if f.scope_id != null then f.scope_id else "user:${currentUser}";
                }
              ) (userCfg.memory.userFacts or [ ]));

            pluginConfigs = {
              "dsh-auth" = {
                mode = authCfg.mode or "auto";
                forwardProxy = authCfg.forwardProxy or { enabled = true; };
                oidc = authCfg.oidc or { enabled = false; };
                ldap = authCfg.ldap or { enabled = false; };
                loopback = {
                  enabled = authCfg.loopback.enabled or true;
                  defaultUser = currentUser;
                  defaultClearance = "Admin";
                };
                peerMesh = authCfg.peerMesh or { enabled = true; };
              };
              "dsh-memory" = {
                facts = allConfiguredFacts;
                maxRecallTokens = systemCfg.memory.maxRecallTokens or 150;
                minRecallThreshold = systemCfg.memory.minRecallThreshold or (-1.5);
              };
              "dsh-mesh" = {
                nodeId = currentHost;
                listenPort = systemCfg.mesh.listenPort or 3891;
                peers = allConfiguredPeers;
              };
            };

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

            patchEntries = render.mkHomePatchEntries {
              inherit mcpServers pluginConfigs;
              persona = systemCfg.persona or null;
              pluginBundleNames = activePluginBundleNames;
              extraEntries = lspPatchEntries;
            };
            homePatch = render.mkHomePatch patchEntries;

            renderedProfiles = systemCfg.profiles or { };
          in
          {
            options.my.features.dev.dsh = {
              enable = lib.mkEnableOption "dsh (DeepSeek Harness) for this Home Manager user";

              instructions = lib.mkOption {
                type = lib.types.nullOr lib.types.path;
                default = ./AGENTS-PROMPT.md;
                description = "AGENTS.md source materialized as the user-global $DSH_HOME/AGENTS.md.";
              };

              settings = lib.mkOption {
                type = lib.types.attrsOf lib.types.anything;
                default = { };
                description = "User-specific settings.yaml override (merged above host defaults).";
              };

              web = {
                enable = lib.mkOption {
                  type = lib.types.bool;
                  default = systemCfg.web.enable or false;
                  description = "Run dsh web as a background systemd user service.";
                };
                port = lib.mkOption {
                  type = lib.types.port;
                  default = systemCfg.web.port or 3080;
                  description = "Port for the dsh web server.";
                };
                host = lib.mkOption {
                  type = lib.types.str;
                  default = systemCfg.web.host or "127.0.0.1";
                  description = "Host/IP address for the dsh web server to bind to.";
                };
                desktopLauncher = lib.mkOption {
                  type = lib.types.bool;
                  default = (osConfig.my.role or "server") != "server";
                  description = "Generate a native desktop launcher via my.features.desktop.webapps.";
                };
              };

              mesh = {
                userPeers = lib.mkOption {
                  type = lib.types.listOf (
                    lib.types.submodule {
                      options = {
                        id = lib.mkOption {
                          type = lib.types.str;
                          description = "Personal peer node identifier.";
                        };
                        endpoint = lib.mkOption {
                          type = lib.types.str;
                          description = "Peer endpoint (host:port or URL).";
                        };
                        tags = lib.mkOption {
                          type = lib.types.listOf lib.types.str;
                          default = [ ];
                          description = "Node tags/capabilities (e.g. personal, laptop).";
                        };
                      };
                    }
                  );
                  default = [ ];
                  description = "Personal cluster peer nodes dedicated to this specific user.";
                };
              };

              memory = {
                userFacts = lib.mkOption {
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
                          default = "user";
                          description = "Lattice security clearance required.";
                        };
                        scope_type = lib.mkOption {
                          type = lib.types.enum [
                            "public"
                            "group"
                            "user"
                            "repo"
                          ];
                          default = "user";
                          description = "Memory scope type (defaults to personal user memory).";
                        };
                        scope_id = lib.mkOption {
                          type = lib.types.nullOr lib.types.str;
                          default = null;
                          description = "Memory scope target ID (e.g. group:dev, repo:nixfiles; defaults to user:username).";
                        };
                      };
                    }
                  );
                  default = [ ];
                  description = "Personal declarative facts and preferences provisioned for this user.";
                };
              };
            };

            config = lib.mkIf userCfg.enable {
              home.packages = [
                (if systemCfg.package or null != null then systemCfg.package else pkgs.custom.dsh)
              ]
              ++ lib.catAttrs "package" (lib.attrValues mcpServers)
              ++ lib.optionals lspEnabled (lib.catAttrs "package" (lib.attrValues activeLspServers));

              home.sessionVariables = lib.optionalAttrs (systemCfg.dshHome or null != null) {
                DSH_HOME = systemCfg.dshHome;
              };

              home.file = lib.mkMerge [
                {
                  ".dsh/settings.yaml" = {
                    text = builtins.toJSON settingsDoc;
                    force = true;
                  };
                }
                (lib.optionalAttrs (homePatch != null) {
                  ".dsh/cordis.patch.yml".text = homePatch;
                })
                (lib.optionalAttrs (userCfg.instructions != null) {
                  ".dsh/AGENTS.md".source = userCfg.instructions;
                })
                (lib.optionalAttrs (osConfig ? sops && osConfig.sops.templates ? "dsh-credentials.yaml") {
                  ".dsh/.credentials.yaml" = {
                    source = config.lib.file.mkOutOfStoreSymlink osConfig.sops.templates."dsh-credentials.yaml".path;
                    force = true;
                  };
                })
                (lib.mapAttrs'
                  (name: profile: {
                    name = ".dsh/profiles/${name}/package.json";
                    value.text = builtins.toJSON (render.mkProfileManifest name profile);
                  })
                  (
                    lib.filterAttrs (
                      _: profile: profile.bundles != null || profile.patchReload != null
                    ) renderedProfiles
                  )
                )
                (lib.optionalAttrs (activePluginDrvs != [ ]) (
                  lib.listToAttrs (
                    # Plugin injection at ~/.dsh/node_modules: it sits on the
                    # Node parent-walk of every profile's patch-layer imports
                    # (profiles/web → profiles → ~/.dsh), and unlike
                    # profiles/node_modules the launcher never writes there
                    # (its healing owns that directory), so a read-only
                    # HM-managed directory is safe.
                    map (drv: {
                      name = ".dsh/node_modules/${drv.dshPluginName}";
                      value.source = "${drv}/lib/node_modules/${drv.dshPluginName}";
                    }) activePluginDrvs
                  )
                ))
                (lib.mapAttrs' (name: profile: {
                  name = ".dsh/profiles/${name}/cordis.patch.yml";
                  value.text = render.mkProfilePatch profile;
                }) (lib.filterAttrs (_: profile: profile.patches != [ ]) renderedProfiles))
              ];

              systemd.user.services.dsh-web = lib.mkIf userCfg.web.enable {
                Unit = {
                  Description = "DeepSeek Harness (dsh) Web UI Service";
                  Documentation = [ "https://github.com/deepseek-ai/deepseek-harness" ];
                  After = [ "network.target" ];
                  X-Restart-Triggers = activePluginDrvs ++ [
                    (builtins.toJSON settingsDoc)
                    (if homePatch != null then homePatch else "")
                  ];
                };

                Service = {
                  Type = "simple";
                  ExecStart = "${
                    if systemCfg.package or null != null then systemCfg.package else pkgs.custom.dsh
                  }/bin/dsh web --no-open --host ${userCfg.web.host} --port ${toString userCfg.web.port}";
                  Restart = "on-failure";
                  RestartSec = "5s";
                  Environment = lib.optionals (systemCfg.dshHome or null != null) [
                    "DSH_HOME=${systemCfg.dshHome}"
                  ];
                };

                Install = {
                  WantedBy = [ "default.target" ];
                };
              };

              my.features.desktop.webapps.apps.dsh =
                lib.mkIf (userCfg.web.enable && userCfg.web.desktopLauncher)
                  {
                    displayName = "DeepSeek Harness";
                    url = "http://${userCfg.web.host}:${toString userCfg.web.port}";
                    icon = "${
                      if systemCfg.package or null != null then systemCfg.package else pkgs.custom.dsh
                    }/lib/dsh/apps/web/public/favicon.svg";
                    comment = "DeepSeek Harness (dsh) Agent Web Interface";
                    categories = [
                      "Development"
                      "Utility"
                    ];
                    wmClass = "dsh";
                  };
            };
          }
        )
      ];
    }
  ];
}
