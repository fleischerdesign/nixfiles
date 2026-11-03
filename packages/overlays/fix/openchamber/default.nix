# OpenChamber Desktop has no pre-lock hook: `app.relaunch()` starts the Electron binary directly and
# therefore bypasses any launcher wrapper, while an environment variable is inherited by the
# relaunched process. This overlay adds the narrow hook upstream lacks, immediately before the
# single-instance lock, so a device token is reconciled on every real start.
#
# The hook executes one configured command and fails closed: status 75 means "another instance owns
# the profile" and is deliberately allowed to continue into the singleton check; any other non-zero
# status stops the launch instead of opening a client without a valid token. The patch is tied to
# 2.6.0 and fails the build when the pinned source moves, rather than silently shipping an
# unpatched desktop.
{ inputs }:
_final: prev:
let
  openchamber = inputs.openchamber.packages.${prev.stdenv.hostPlatform.system};
in
{
  openchamber = openchamber.openchamber;
  openchamber-desktop = openchamber.openchamber-desktop.overrideAttrs (previous: {
    postPatch = (previous.postPatch or "") + ''
      node ${./patch-entry-provision-hook.mjs}
    '';
  });
}
