{
  config,
  lib,
  ...
}:

let
  cfg = config.my.features.services.hermes-agent;
in
{
  options.my.features.services.hermes-agent = {
    enable = lib.mkEnableOption "Hermes Agent (WhatsApp AI Assistant)";
  };

  config = lib.mkIf cfg.enable {
    users.users.philipp.extraGroups = [ "hermes" ];

    sops.secrets.hermes_agent_env = {
      owner = "hermes";
    };

    services.hermes-agent = {
      enable = true;
      addToSystemPackages = true;
      environmentFiles = [ config.sops.secrets.hermes_agent_env.path ];
      settings = {
        model.provider = "deepseek";
        model.default = "deepseek-v4-pro";
        display.tool_progress = "all";
      };
    };
  };
}
