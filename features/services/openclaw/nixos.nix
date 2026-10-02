{
  config,
  lib,
  pkgs,
  inputs,
  fleetConfigs,
  usersDir,
  ...
}:
let
  cfg = config.my.features.services.openclaw;
  runtime = import ./runtime.nix { inherit lib pkgs; };
  openclaw = import ./build.nix { inherit lib pkgs inputs; };
  ports = import ./ports.nix;
  accessGroup = config.my.directory.groups.${cfg.accessGroup} or null;
  members =
    if accessGroup != null && accessGroup.state == "present" && accessGroup.members != null then
      accessGroup.members
    else
      [ ];
  profileModules =
    (import ../../../lib/discovery.nix { inherit lib; }).findNamed "openclaw.nix"
      usersDir;
  instanceType = lib.types.submodule (
    { name, ... }: {
      options = runtime.options // {
        owner = lib.mkOption {
          type = lib.types.str;
          default = name;
          internal = true;
          description = "Authentik username owning this gateway, derived from the profile key.";
        };
        gatewayHost = lib.mkOption {
          type = lib.types.str;
          default = cfg.gatewayHost;
          description = "Inventory placement of this user's gateway.";
        };
        port = lib.mkOption {
          type = lib.types.port;
          default = 18000 + lib.fromHexString (builtins.substring 0 3 (builtins.hashString "sha256" name));
          description = "Stable username-derived gateway port; explicit overrides resolve collisions without renumbering other people.";
        };
        subdomain = lib.mkOption {
          type = lib.types.str;
          default = "${name}.ai";
          description = "Personal publication prefix under the topology domain.";
        };
        stateDir = lib.mkOption {
          type = lib.types.str;
          default = "/var/lib/openclaw/instances/${name}";
          description = "Private mutable gateway state.";
        };
        nodeHosts = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = lib.attrNames (
            lib.filterAttrs (
              _: system:
              lib.any (node: node.instance == name && node.gateway == cfg.users.${name}.gatewayHost) (
                lib.attrValues system.config.my.features.services.openclaw.nodes
              )
            ) (fleetConfigs.systems config)
          );
          description = "Inventory hosts admitted for native nodes, derived from their placements.";
        };
        secrets = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = "Environment variable to SOPS secret name, rendered into private per-instance files.";
        };
        backup = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Register verified native archives with the backup provider.";
        };
        fleet = {
          enable = lib.mkEnableOption "root-equivalent administration on this host";
          hosts = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Inventory targets for fleet SSH administration.";
          };
          privateKeyFile = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Private fleet credential readable by this gateway; never a node tunnel key.";
          };
          publicKey = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Corresponding public credential authorized only on the selected targets.";
          };
        };
        apps = {
          enable = lib.mkEnableOption "the separate native MCP Apps origin";
          port = lib.mkOption {
            type = lib.types.port;
            default = cfg.users.${name}.port + ports.apps;
            description = "MCP Apps (sandbox host) listener port. OpenClaw derives this as gateway+${toString ports.apps}, and the Browser Control service claims gateway+${toString ports.browserControl} with its managed Chrome CDP band from gateway+${toString ports.browserCdpStart}, so the derived value cannot collide.";
          };
          subdomain = lib.mkOption {
            type = lib.types.str;
            default = "sandbox.${name}.ai";
            description = "Isolated MCP Apps origin prefix.";
          };
        };
        publishing = {
          enable = lib.mkEnableOption "public application publishing through private per-app Unix sockets";
          port = lib.mkOption {
            type = lib.types.port;
            default = cfg.users.${name}.port + ports.publishing;
            description = "Mesh application router port, derived from the gateway by default. The offset clears the Browser Control and managed Chrome CDP band (gateway+${toString ports.browserControl}..gateway+${toString ports.browserCdpEnd}) so the derived value cannot collide with an OpenClaw-internal listener.";
          };
          subdomain = lib.mkOption {
            type = lib.types.str;
            default = "pub.${name}.ai";
            description = "Dedicated public application namespace, separate from gateway and MCP Apps cookies.";
          };
        };
        google = {
          enable = lib.mkEnableOption "Google Workspace with a private gog file keyring";
          credentialsSecret = lib.mkOption {
            type = lib.types.str;
            description = "SOPS OAuth client JSON; interactive consent remains runtime state.";
          };
        };
        obsidianBridge = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Existing LiveSync bridge instance granted writable access as this gateway identity.";
        };
      };
    }
  );
  nodeType = lib.types.submodule {
    options = runtime.options // {
      gateway = lib.mkOption {
        type = lib.types.str;
        description = "Inventory host running the gateway.";
      };
      instance = lib.mkOption {
        type = lib.types.str;
        description = "Personal instance on that gateway.";
      };
      session = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Run in the primary user's graphical session instead of a system service.";
      };
    };
  };
  systems = fleetConfigs.systems config;
  grants = lib.concatLists (
    lib.mapAttrsToList (
      source: system:
      let
        feature = system.config.my.features.services.openclaw;
      in
      lib.optionals feature.enable (
        lib.mapAttrsToList
          (_: instance: {
            inherit source;
            inherit (instance) fleet;
          })
          (
            lib.filterAttrs (
              _: instance: instance.fleet.enable && lib.elem config.networking.hostName instance.fleet.hosts
            ) feature.instances
          )
      )
    ) systems
  );
  referencedHosts =
    lib.concatMap (instance: instance.nodeHosts ++ instance.fleet.hosts) (lib.attrValues cfg.instances)
    ++ map (node: node.gateway) (lib.attrValues cfg.nodes);
in
{
  imports = [
    ./gateways.nix
    ./nodes.nix
    ./integrations.nix
  ]
  ++ profileModules;
  options.my.features.services.openclaw = {
    enable = lib.mkEnableOption "personal OpenClaw gateways and person-bound native nodes";
    package = lib.mkOption {
      type = lib.types.package;
      default = openclaw.package;
      defaultText = lib.literalExpression "the release resolved by features/services/openclaw/build.nix";
      description = "Upstream-pinned OpenClaw runtime and tools for the release declared in release.nix.";
    };
    accessGroup = lib.mkOption {
      type = lib.types.str;
      default = "ai-users";
      description = "Declaratively managed identity group whose members receive personal gateways.";
    };
    gatewayHost = lib.mkOption {
      type = lib.types.str;
      description = "Default inventory host for personal gateway placement.";
    };
    users = lib.mkOption {
      type = lib.types.attrsOf instanceType;
      default = { };
      description = "Personal profiles; group membership decides which profiles are provisioned.";
    };
    instances = lib.mkOption {
      type = lib.types.attrsOf instanceType;
      internal = true;
      readOnly = true;
      description = "Group-authorized personal gateways placed on this host.";
    };
    node = lib.mkOption {
      type = lib.types.submodule {
        options = runtime.options // {
          enable = lib.mkEnableOption "a native node for this host's group-authorized primary user";
          session = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Bind the automatic personal node to the graphical session.";
          };
        };
      };
      default = { };
      description = "Automatic person-bound node on a personal device.";
    };
    nodes = lib.mkOption {
      type = lib.types.attrsOf nodeType;
      default = { };
      description = "Node placements executed as this host's primary user.";
    };
    sessionNodes = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      internal = true;
      description = "Derived account-scope node units, consumed by the Home Manager half.";
    };
  };
  config = {
    my.features.services.openclaw = {
      users = lib.genAttrs members (_: { });
      instances = lib.filterAttrs (
        name: profile:
        cfg.enable && lib.elem name members && profile.gatewayHost == config.networking.hostName
      ) cfg.users;
      nodes = lib.optionalAttrs (cfg.node.enable && lib.elem config.my.user.primary members) {
        ${config.my.user.primary} = builtins.removeAttrs cfg.node [ "enable" ] // {
          gateway = cfg.users.${config.my.user.primary}.gatewayHost;
          instance = config.my.user.primary;
          environment = cfg.node.environment // {
            OPENCLAW_ALLOW_INSECURE_PRIVATE_WS = "1";
          };
        };
      };
    };
    my.features.system.networking.ssh = {
      admitsHosts = lib.unique (map (grant: grant.source) grants);
      extraDeployKeys = lib.unique (
        lib.concatMap (grant: lib.optional (grant.fleet.publicKey != null) grant.fleet.publicKey) grants
      );
    };
    home-manager.sharedModules = [ ./home.nix ];
    assertions = lib.optionals cfg.enable [
      {
        assertion = accessGroup != null && accessGroup.state == "present" && accessGroup.members != null;
        message = "OpenClaw provisioning requires a present directory accessGroup with explicitly Nix-owned membership.";
      }
      {
        assertion = lib.all (value: value) (
          lib.mapAttrsToList (name: profile: profile.owner == name) cfg.users
        );
        message = "OpenClaw profile keys must equal their owner identity.";
      }
      {
        # A profile names plugin identifiers; the catalogue decides the package. An unknown identifier
        # must fail here, not produce a gateway that silently starts without a plugin the profile
        # believes it enabled.
        assertion = lib.all (
          instance: lib.all (name: lib.hasAttr name openclaw.all) instance.enabledPlugins
        ) (lib.attrValues cfg.users);
        message = "OpenClaw enabledPlugins must name identifiers declared in features/services/openclaw/plugins.nix.";
      }
      {
        # `contribution` is load-bearing: at most one enabled plugin may claim to implement the web
        # search provider, and a profile that names one must name the enabled plugin. This is what
        # keeps the catalogue's classification and the native `tools.web.search.provider` from
        # disagreeing.
        assertion = lib.all (
          instance:
          let
            webSearch = lib.filter (
              name: (openclaw.all.${name}.contribution or null) == "webSearch"
            ) instance.enabledPlugins;
            declared = instance.settings.tools.web.search.provider or null;
          in
          lib.length webSearch <= 1
          && (webSearch == [ ] || declared == null || declared == lib.head webSearch)
        ) (lib.attrValues cfg.users);
        message = "At most one enabled plugin may contribute web search, and tools.web.search.provider must name it.";
      }
      {
        # Every listener an instance occupies on its gateway host, including the ports OpenClaw
        # derives internally from the gateway port. Browser Control is gateway+2 and its managed
        # Chrome CDP range is gateway+11..gateway+110 (extensions/browser/src/config/port-defaults.ts);
        # MCP Apps and the publishing router are declared. Listing them here is what makes the
        # derived MCP Apps port a checked decision rather than a hope: the two derived ranges used to
        # collide because MCP Apps was placed at gateway+2, the Browser Control port.
        assertion =
          let
            reserved =
              profile:
              let
                # The band OpenClaw allocates managed Chrome profiles from.
                cdp = lib.range (profile.port + ports.browserCdpStart) (profile.port + ports.browserCdpEnd);
              in
              [
                profile.port
                (profile.port + ports.browserControl)
              ]
              ++ cdp
              ++ lib.optional profile.apps.enable profile.apps.port
              ++ lib.optional profile.publishing.enable profile.publishing.port;
            occupied = lib.concatMap reserved (lib.attrValues cfg.instances);
          in
          lib.length occupied == lib.length (lib.unique occupied);
        message = "OpenClaw listener ports, including the derived Browser Control and managed Chrome CDP ports, must be unique on their gateway host.";
      }
      {
        assertion = lib.all (name: lib.hasAttr name config.my.topology.hosts) referencedHosts;
        message = "OpenClaw placements and fleet grants must reference inventory hosts.";
      }
      {
        assertion = lib.all (
          node: node.instance == config.my.user.primary && lib.elem node.instance members
        ) (lib.attrValues cfg.nodes);
        message = "OpenClaw nodes must belong to this host's group-authorized primary identity.";
      }
      {
        assertion = lib.all (
          node:
          systems.${node.gateway}.config.my.features.services.openclaw.enable
          && lib.hasAttr node.instance systems.${node.gateway}.config.my.features.services.openclaw.instances
        ) (lib.attrValues cfg.nodes);
        message = "OpenClaw nodes must reference an enabled gateway instance.";
      }
      {
        assertion = lib.all (
          instance: (instance.fleet.privateKeyFile == null) == (instance.fleet.publicKey == null)
        ) (lib.attrValues cfg.instances);
        message = "OpenClaw fleet credentials require both privateKeyFile and publicKey.";
      }
    ];
  };
}
