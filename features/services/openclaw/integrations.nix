{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.my.features.services.openclaw;
  googleInstances = lib.filterAttrs (_: instance: instance.google.enable) cfg.instances;
  bridgeInstances = lib.filterAttrs (_: instance: instance.obsidianBridge != null) cfg.instances;
  gog = inputs.openclaw.inputs.nix-openclaw-tools.packages.${pkgs.stdenv.hostPlatform.system}.gogcli;
  googleUnit =
    name: instance:
    let
      id = "openclaw-${name}";
      directory = "${instance.stateDir}/google";
    in
    lib.nameValuePair "${id}-google" {
      description = "Google Workspace client and private keyring (${name})";
      wantedBy = [ "multi-user.target" ];
      after = [ "sops-nix.service" ];
      before = [ "${id}.service" ];
      restartTriggers = [ config.sops.templates."${id}-google-client".content ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = id;
        Group = id;
        UMask = "0077";
      };
      script = ''
        set -euo pipefail
        if [ ! -e ${lib.escapeShellArg "${directory}/keyring-password"} ]; then
          temporary="$(mktemp ${lib.escapeShellArg "${directory}/.keyring.XXXXXXXX"})"
          trap 'rm -f -- "$temporary"' EXIT
          ${pkgs.openssl}/bin/openssl rand -base64 32 > "$temporary"
          mv -n -- "$temporary" ${lib.escapeShellArg "${directory}/keyring-password"}
        fi
        export GOG_CONFIG_DIR=${lib.escapeShellArg directory}
        # The file-backed keyring needs its password non-interactively; without it the CLI fails with
        # "no TTY available for keyring file backend password prompt". Read the file created above
        # rather than prompting.
        export GOG_KEYRING_BACKEND=file
        export GOG_KEYRING_PASSWORD="$(cat ${lib.escapeShellArg "${directory}/keyring-password"})"
        ${gog}/bin/gog auth credentials ${config.sops.templates."${id}-google-client".path}
      '';
    };
in
{
  config = lib.mkIf cfg.enable {
    sops.secrets = lib.genAttrs (lib.mapAttrsToList (
      _: instance: instance.google.credentialsSecret
    ) googleInstances) (_: { });
    sops.templates = lib.mapAttrs' (
      name: instance:
      lib.nameValuePair "openclaw-${name}-google-client" {
        owner = "openclaw-${name}";
        mode = "0400";
        content = config.sops.placeholder.${instance.google.credentialsSecret};
        restartUnits = [ "openclaw-${name}-google.service" ];
      }
    ) googleInstances;
    systemd.services = lib.mkMerge [
      (lib.listToAttrs (lib.mapAttrsToList googleUnit googleInstances))
      (lib.mapAttrs' (
        name: _:
        lib.nameValuePair "openclaw-${name}" {
          requires = [ "openclaw-${name}-google.service" ];
          after = [ "openclaw-${name}-google.service" ];
        }
      ) googleInstances)
    ];
    systemd.tmpfiles.rules = lib.mapAttrsToList (
      name: instance: "d ${instance.stateDir}/google 0700 openclaw-${name} openclaw-${name} - -"
    ) googleInstances;
    my.features.services.obsidian-livesync-bridge.instances = lib.mkMerge (
      lib.mapAttrsToList (name: instance: {
        ${instance.obsidianBridge} = {
          user = lib.mkForce "openclaw-${name}";
          group = lib.mkForce "openclaw-${name}";
          # The vault stays a replica: CouchDB is the source of truth, the bridge is bidirectional, and
          # the CouchDB host is backed up. Declaring it regenerable is what keeps it out of the backup
          # exclude collision - the gateway's own state directory is excluded, and restic excludes are
          # global, so a vault inside that tree could not be backed up even if it were listed.
        };
      }) bridgeInstances
    );
    assertions = [
      {
        assertion = lib.all (
          instance:
          (config.my.features.services.obsidian-livesync-bridge.instances.${instance.obsidianBridge}.enable
            or false
          )
          && config.my.features.services.obsidian-livesync-bridge.enable
        ) (lib.attrValues bridgeInstances);
        message = "OpenClaw writable vault references require an enabled LiveSync bridge.";
      }
    ];
  };
}
