# Read-only compiled views shared by consumers. Each domain owns the values it derives; this module
# owns the common projection namespace and its stable output shapes.
{ lib, ... }:
{
  options.my.contracts.projections = lib.mkOption {
    type = lib.types.submodule {
      options = {
        fqdns = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          readOnly = true;
          description = "Every service FQDN derived from the contract fleet.";
        };
        hostFqdns = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          readOnly = true;
          description = "Every host FQDN of the node plane.";
        };
        hostFqdnOf = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          readOnly = true;
          description = "Host name to node-plane FQDN mapping.";
        };
        deviceFqdnOf = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          readOnly = true;
          description = "Device name to node-plane FQDN mapping.";
        };
        aliases = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          readOnly = true;
          description = "Deprecation report of legacy names still published as aliases.";
        };
        backup = lib.mkOption {
          type = lib.types.submodule {
            options = {
              paths = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                readOnly = true;
                description = "Paths required by enabled service backup declarations.";
              };
              exclude = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                readOnly = true;
                description = "Paths excluded by service backup/storage declarations.";
              };
              preBackup = lib.mkOption {
                type = lib.types.listOf lib.types.lines;
                readOnly = true;
                description = "Preparation hooks required before a backup.";
              };
              postBackup = lib.mkOption {
                type = lib.types.listOf lib.types.lines;
                readOnly = true;
                description = "Cleanup hooks required after a backup.";
              };
            };
          };
          description = "Backend-neutral backup requirements compiled from service contracts.";
        };
      };
    };
    description = "Read-only projections compiled from domain contracts.";
  };
}
