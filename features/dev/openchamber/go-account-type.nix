lib:
lib.types.listOf (
  lib.types.submodule {
    options = {
      slot = lib.mkOption {
        type = lib.types.strMatching "[a-z0-9][a-z0-9-]{0,30}";
        description = "Stable managed Go account slot.";
      };
      apiKeySecret = lib.mkOption {
        type = lib.types.str;
        description = "SOPS secret staged exclusively through systemd LoadCredential.";
      };
    };
  }
)
