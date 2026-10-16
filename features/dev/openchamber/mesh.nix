# Fleet intent is projected from enabled services; credentials never enter this model.
{
  config,
  lib,
  flake ? null,
  ...
}:
let
  cfg = config.my.features.dev.openchamber;
  hostname = config.networking.hostName;
  fleet = lib.filterAttrs (
    _: host:
    let
      peer = host.config.my.features.dev.openchamber;
    in
    peer.enable && peer.server.enable && peer.mesh.enable
  ) (if flake == null then { } else flake.nixosConfigurations);
  addressOf = host: host.config.my.topology.hosts.${host.config.networking.hostName}.wireguardIpv4;
  urlOf =
    host: "http://${addressOf host}:${toString host.config.my.features.dev.openchamber.server.port}";
  enabledTargets =
    if cfg.enable && cfg.mesh.enable && cfg.desktop.enable then cfg.mesh.targets else [ ];
in
{
  options.my.features.dev.openchamber.mesh = {
    enable = lib.mkEnableOption "Nix-managed OpenChamber connections and client grants";
    targets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default =
        if cfg.enable && cfg.mesh.enable && cfg.desktop.enable then
          lib.filter (name: name != hostname) (builtins.attrNames fleet)
        else
          [ ];
      description = "Fleet instances this desktop may access. Defaults to every other managed instance.";
    };
    manifest = lib.mkOption {
      type = lib.types.attrs;
      readOnly = true;
      internal = true;
    };
  };

  config = {
    assertions = lib.optionals (cfg.enable && cfg.mesh.enable) [
      {
        assertion = cfg.server.enable;
        message = "OpenChamber mesh management requires this host's server.";
      }
      {
        assertion = cfg.desktop.enable || cfg.mesh.targets == [ ];
        message = "An OpenChamber server without a desktop cannot declare outgoing mesh targets.";
      }
      {
        assertion = lib.all (name: name != hostname && builtins.hasAttr name fleet) cfg.mesh.targets;
        message = "OpenChamber mesh targets must name other enabled fleet instances.";
      }
      {
        assertion = builtins.length cfg.mesh.targets == builtins.length (lib.unique cfg.mesh.targets);
        message = "OpenChamber mesh targets must be unique.";
      }
    ];
    my.features.dev.openchamber.mesh.manifest = {
      client = hostname;
      hosts = map (name: {
        inherit name;
        url = urlOf fleet.${name};
      }) enabledTargets;
      server =
        if cfg.enable && cfg.server.enable then
          {
            url = "http://${config.my.topology.hosts.${hostname}.wireguardIpv4}:${toString cfg.server.port}";
            clients = builtins.attrNames (
              lib.filterAttrs (
                _: host:
                host.config.my.features.dev.openchamber.desktop.enable
                && builtins.elem hostname host.config.my.features.dev.openchamber.mesh.targets
              ) (if cfg.mesh.enable then fleet else { })
            );
          }
        else
          null;
    };
  };
}
