# Two narrow source corrections on the pinned OpenChamber 2.6.0 package. Both fail the build when
# the pinned sources move, rather than silently shipping an unpatched client.
#
# 1. Desktop provisioning hook (patch-entry-provision-hook.mjs): OpenChamber Desktop has no pre-lock
#    hook - `app.relaunch()` starts the Electron binary directly and therefore bypasses any launcher
#    wrapper, while an environment variable is inherited by the relaunched process. This overlay
#    adds the hook immediately before the single-instance lock, so a device token is reconciled on
#    every real start. Status 75 means "another instance owns the profile" and continues into the
#    singleton check; any other non-zero status stops the launch.
#
# 2. OpenCode Go limit failover (patch-go-limit.mjs): OpenChamber 2.6.0 omits OpenCode's
#    `provider.go-limit` from both limit-failover boundaries (policy.js and the generated plugin
#    source in runtime.js). The patch adds the one error type to both, so the native account
#    switching upstream already implements reacts to a spent Go plan. It is obsolete as soon as
#    upstream lists the type at both boundaries: the script then exits 78 and names the files to
#    remove. See docs/openchamber.md, "OpenCode Go accounts".
#
# The core package's installPhase is extended instead of its build: only the runtime server files
# copied there change, so the web assets and dependency tree are not rebuilt. Both consumers - the
# server wrapper and the desktop app - are repointed at the patched core.
{ inputs }:
_final: prev:
let
  lib = prev.lib;
  upstream = inputs.openchamber.packages.${prev.stdenv.hostPlatform.system};
  core = upstream.openchamber.passthru.core;

  patchedCore = core.overrideAttrs (previous: {
    installPhase = (previous.installPhase or "") + ''
      node ${./patch-go-limit.mjs} "$out/lib/openchamber"
    '';
  });

  replaceCore = text: lib.replaceStrings [ "${core}" ] [ "${patchedCore}" ] text;
  coreText = builtins.unsafeDiscardStringContext "${core}";
in
{
  openchamber = upstream.openchamber.overrideAttrs (previous: {
    # The wrapper's script names the core store path literally; if that stops being true the
    # replacement silently leaves the unpatched core behind, so fail the evaluation instead.
    installPhase =
      assert lib.hasInfix coreText previous.installPhase;
      replaceCore previous.installPhase;
    passthru = previous.passthru // {
      core = patchedCore;
    };
  });

  openchamber-desktop = upstream.openchamber-desktop.overrideAttrs (previous: {
    buildPhase =
      assert lib.hasInfix coreText previous.buildPhase;
      replaceCore previous.buildPhase;
    postPatch = (previous.postPatch or "") + ''
      node ${./patch-entry-provision-hook.mjs}
    '';
    passthru = previous.passthru // {
      openchamberCore = patchedCore;
    };
  });
}
