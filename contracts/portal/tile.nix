# A visible view of a service's named endpoint. It owns copy and grouping, not listener facts.
{ lib }:
lib.types.submodule {
  options = {
    endpoint = lib.mkOption {
      type = lib.types.str;
      description = "Endpoint id within this service.";
    };
    show = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Publish this entry in the portal.";
    };
    displayName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Human-readable name of this entry.";
    };
    category = lib.mkOption {
      type = lib.types.str;
      default = "Services";
      description = "Portal category and SSO application group.";
    };
    icon = lib.mkOption {
      type = lib.types.str;
      default = "default";
      description = "Portal icon identifier.";
    };
    description = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Summary copy keyed by locale.";
    };
  };
}
