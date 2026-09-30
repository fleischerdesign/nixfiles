{ config, lib, ... }:
let
  cfg = config.my.features.system.smtp;
in
{
  options.my.features.system.smtp = {
    enable = lib.mkEnableOption "shared outbound SMTP credentials";
    host = lib.mkOption {
      type = lib.types.str;
      description = "Outbound SMTP server.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 587;
      description = "Outbound SMTP port.";
    };
    tls = lib.mkOption {
      type = lib.types.enum [
        "starttls"
        "implicit"
      ];
      default = "starttls";
      description = "Required SMTP encryption mode; certificate verification remains enabled.";
    };
    fromAddress = lib.mkOption {
      type = lib.types.str;
      description = "Default sender address for application mail.";
    };
    usernameSecret = lib.mkOption {
      type = lib.types.str;
      default = "infra/smtp/username";
      description = "SOPS key containing the SMTP username.";
    };
    passwordSecret = lib.mkOption {
      type = lib.types.str;
      default = "infra/smtp/password";
      description = "SOPS key containing the SMTP password.";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.${cfg.usernameSecret} = { };
    sops.secrets.${cfg.passwordSecret} = { };
  };
}
