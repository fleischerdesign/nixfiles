# features/services/openclaw/lib/command-surface.nix
# The single catalogue of OpenClaw node command *families*.
#
# Why a catalogue: the gateway gates node commands in two layers - the platform/plugin defaults it
# derives itself, and a flat `gateway.nodes.commands.allow` list of exact command ids for everything
# dangerous or plugin-owned. Hand-writing that list per host means every command name exists in two
# places (host config and upstream release notes), and nothing checks the two agree. Here a host
# declares *capabilities*; the command ids, the file-transfer path policy and the platform
# constraints are projected from this one table.
#
# `default` commands are part of the platform or plugin default surface and need no gateway opt-in;
# `allow` commands are dangerous or plugin-gated and are only effective when the gateway names them
# in `gateway.nodes.commands.allow`. Private worker-internal commands (`worker.*`) are not listed at
# all: upstream removes them from every advertised and configurable surface.
{ lib }:
let
  families = {
    system = {
      platforms = [
        "linux"
        "macos"
        "windows"
        "unknown"
      ];
      commands.default = [
        "system.run"
        "system.run.prepare"
        "system.which"
        "system.execApprovals.get"
        "system.execApprovals.set"
        "system.notify"
        "fs.listDir"
        "terminal.upload"
      ];
      commands.allow = [ ];
    };

    browser = {
      platforms = [
        "linux"
        "macos"
        "windows"
      ];
      commands.default = [
        "browser.proxy"
        "browser.proxy.upload.v1"
      ];
      commands.allow = [ ];
    };

    mcp = {
      platforms = [
        "linux"
        "macos"
        "windows"
      ];
      commands.default = [ "mcp.tools.call.v1" ];
      commands.allow = [ ];
    };

    local-inference = {
      platforms = [
        "linux"
        "macos"
        "windows"
      ];
      commands.default = [
        "ollama.chat"
        "ollama.models"
      ];
      commands.allow = [ ];
    };

    agent-cli = {
      platforms = [
        "linux"
        "macos"
        "windows"
      ];
      commands.default = [ "agent.cli.claude.run.v1" ];
      commands.allow = [ ];
    };

    logbook = {
      platforms = [
        "linux"
        "macos"
        "windows"
      ];
      commands.default = [ "logbook.snapshot" ];
      commands.allow = [ ];
    };

    files-read = {
      platforms = [
        "linux"
        "macos"
        "windows"
      ];
      commands.default = [ ];
      commands.allow = [
        "file.fetch"
        "dir.list"
      ];
      fileTransfer.read = true;
    };

    files-write = {
      platforms = [
        "linux"
        "macos"
        "windows"
      ];
      commands.default = [ ];
      commands.allow = [
        "file.fetch"
        "dir.fetch"
        "file.write"
      ];
      fileTransfer.read = true;
      fileTransfer.write = true;
    };

    screen = {
      platforms = [
        "linux"
        "macos"
        "windows"
      ];
      commands.default = [ "screen.snapshot" ];
      commands.allow = [ "screen.record" ];
    };

    computer = {
      platforms = [
        "linux"
        "macos"
        "windows"
      ];
      commands.default = [ ];
      commands.allow = [ "computer.act" ];
    };

    camera = {
      platforms = [
        "linux"
        "ios"
        "android"
        "macos"
        "windows"
      ];
      commands.default = [ "camera.list" ];
      commands.allow = [
        "camera.snap"
        "camera.clip"
        "camera.ptz.control"
      ];
    };

    location = {
      platforms = [
        "linux"
        "ios"
        "android"
        "macos"
      ];
      commands.default = [ "location.get" ];
      commands.allow = [ ];
    };

    talk = {
      platforms = [
        "ios"
        "android"
        "macos"
      ];
      commands.default = [
        "talk.ptt.start"
        "talk.ptt.stop"
        "talk.ptt.cancel"
        "talk.ptt.once"
      ];
      commands.allow = [ ];
    };

    mobile-device = {
      platforms = [
        "ios"
        "android"
      ];
      commands.default = [
        "device.info"
        "device.status"
        "device.apps"
        "device.permissions"
        "device.health"
        "notifications.list"
        "notifications.actions"
      ];
      commands.allow = [ ];
    };

    mobile-personal = {
      platforms = [
        "ios"
        "android"
      ];
      commands.default = [
        "contacts.search"
        "calendar.events"
        "reminders.list"
        "photos.latest"
        "motion.activity"
        "motion.pedometer"
      ];
      commands.allow = [
        "contacts.add"
        "calendar.add"
        "reminders.add"
        "sms.send"
        "sms.search"
        "health.summary"
      ];
    };
  };

  familyNames = builtins.attrNames families;

  # Named bundles so a host declares intent, not a list. `node-linux` is the full surface a Linux
  # node host can serve; `node-mobile` the one the Play-Store companion app declares; `full` is the
  # union and is what a gateway grants when it wants to withhold nothing.
  profiles = {
    node-linux = [
      "system"
      "browser"
      "mcp"
      "local-inference"
      "agent-cli"
      "logbook"
      "files-read"
      "files-write"
      "screen"
      "computer"
      "camera"
      "location"
    ];
    node-mobile = [
      "mobile-device"
      "mobile-personal"
      "camera"
      "location"
      "talk"
      "screen"
    ];
    full = familyNames;
  };

  # One command id per family/kind, order-stable and deduplicated (file-transfer shares `file.fetch`
  # between `files-read` and `files-write`).
  commandsOf =
    { capabilities, kind }:
    lib.unique (
      lib.concatMap (capability: families.${capability}.commands.${kind} or [ ]) capabilities
    );

  platformsOf =
    capabilities:
    lib.unique (lib.concatMap (capability: families.${capability}.platforms) capabilities);

  # Whether a capability is offered on the platform the declarer runs on; an assertion uses this so a
  # camera capability on a platform without the plugin fails at build time instead of silently doing
  # nothing.
  supports = { capability, platform }: builtins.elem platform families.${capability}.platforms;

  # The `plugins.entries.file-transfer.config` fragment. Path policy is deny-by-default upstream, so
  # a grant needs both the commands (`files-*` families) and an allow pattern here.
  fileTransferPolicy =
    {
      capabilities,
      ask ? "off",
      followSymlinks ? true,
      maxBytes ? 67108864,
      allowReadPaths ? [ "/**" ],
      allowWritePaths ? [ "/**" ],
    }:
    let
      read = lib.any (capability: families.${capability}.fileTransfer.read or false) capabilities;
      write = lib.any (capability: families.${capability}.fileTransfer.write or false) capabilities;
    in
    lib.optionalAttrs (read || write) {
      policyVersion = 2;
      nodes."*" = {
        inherit
          ask
          followSymlinks
          maxBytes
          ;
        allowReadPaths = if read then allowReadPaths else [ ];
        allowWritePaths = if write then allowWritePaths else [ ];
      };
    };
in
{
  inherit families familyNames profiles;
  defaultCommands =
    capabilities:
    commandsOf {
      inherit capabilities;
      kind = "default";
    };
  allowCommands =
    capabilities:
    commandsOf {
      inherit capabilities;
      kind = "allow";
    };
  inherit platformsOf supports fileTransferPolicy;
}
