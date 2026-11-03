# AI runtime resources: the policy fragments and native skill tree shared by interactive coding
# runtimes. The resources are runtime-neutral; a consumer binds the paths it needs.
#
# This feature is deliberately not host-wide. It does not write `/etc/opencode` or any other
# machine-wide configuration: a consumer is a service whose own environment receives the native
# config content. That keeps a policy from applying to every user of a host and leaves a user's
# own OpenCode config and skills editable.
{
  config,
  lib,
  ...
}:

let
  cfg = config.my.features.ai.resources;
  resources = import ./lib { inherit lib; };

  # Content-addressed inputs: a change to a document outside these trees does not move the store
  # path, and a change to a policy or skill does. The whole tree is copied, so relative references,
  # scripts and assets inside a skill keep working.
  policiesRoot = builtins.path {
    path = ./policies;
    name = "ai-resources-policies";
  };
  skillsRoot = builtins.path {
    path = ./skills;
    name = "ai-resources-skills";
  };

  policies = resources.discoverPolicies policiesRoot;
  skills = resources.discoverSkills skillsRoot;

  opencodeConfig = resources.render {
    namespaces = [
      "common"
      "opencode"
    ];
    inherit policies skillsRoot;
  };
in
{
  options.my.features.ai.resources = {
    enable = lib.mkEnableOption "the AI runtime resources";

    consumers.openchamber.enable = lib.mkEnableOption ''
      binding the resources to the OpenChamber-managed OpenCode child. The child receives the native
      `instructions` and `skills` config keys through `OPENCODE_CONFIG_CONTENT`; OpenChamber's own
      managed plugin and permission file is not touched.
    '';
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = skills != [ ];
        message = "ai-resources: `skills/` contains no skill; a resource tree without a resource is disabled by deleting the enable, not by shipping an empty directory";
      }
      {
        assertion = !cfg.consumers.openchamber.enable || config.my.features.dev.openchamber.server.enable;
        message = "ai-resources: `consumers.openchamber.enable` requires `my.features.dev.openchamber.server.enable` on the same host";
      }
      {
        assertion = !cfg.consumers.openchamber.enable || config.services.openchamber.enable;
        message = "ai-resources: `consumers.openchamber.enable` requires the OpenChamber service";
      }
    ];

    # A service-scoped native config layer. OpenCode combines every config document: the
    # `instructions` and `skills` arrays from this content sit beside OpenChamber's managed
    # `plugins`/`permissions` file and the user's global/project config, replacing none of them.
    # `OPENCODE_CONFIG` is intentionally left unset, so OpenChamber keeps ownership of its own file.
    systemd.services.openchamber.environment = lib.mkIf cfg.consumers.openchamber.enable {
      OPENCODE_CONFIG_CONTENT = builtins.toJSON opencodeConfig;
    };
  };
}
