# The OpenClaw feature's derived values, measured rather than asserted in prose.
#
# Three failure modes motivated this check. First, MCP Apps was hand-numbered at the Browser Control
# port (gateway+2), which only surfaces when both listeners actually start. Second, a plugin loaded
# from `plugins.load.paths` carries no trusted install record, so a plugin that touches a trust-gated
# runtime surface fails at registration. Third - and this is the one that matters most - copying files
# into the gateway only proves our own writes: whether OpenClaw actually *discovers and loads* them is
# a separate fact. The check therefore runs the built gateway binary and asks it.
{
  lib,
  pkgs,
  self,
  inputs,
  ...
}:
let
  host = self.nixosConfigurations.cld-ops-01;
  openclaw = import ../features/services/openclaw/build.nix {
    inherit lib pkgs inputs;
  };
  ports = import ../features/services/openclaw/ports.nix;
  feature = host.config.my.features.services.openclaw;
  # Every instance the host actually provisions, not every profile that exists.
  instances = lib.attrValues feature.instances;
  pluginIds = lib.concatStringsSep "," (lib.attrNames openclaw.all);
  config = host.config.environment.etc."openclaw/openclaw-philipp.json".source;
in
assert feature.enable;
assert instances != [ ];
# The declared MCP Apps port is the derived default, not a hand-numbered value.
assert lib.all (instance: instance.apps.port == instance.port + ports.apps) instances;
# The derived listeners are distinct and clear of OpenClaw's own CDP band, and the publishing router
# cannot land inside that band either.
assert lib.all (
  instance:
  instance.port + ports.browserControl < instance.port + ports.browserCdpStart
  && instance.publishing.port > instance.port + ports.browserCdpEnd
) instances;
# Every identifier a profile names resolves to a packaged plugin of the declared release.
assert lib.all (instance: lib.all (name: lib.hasAttr name openclaw.all) instance.enabledPlugins) (
  lib.attrValues feature.users
);
# The loader must fail loudly on a malformed plugin. Pointing it at each fixture proves the negative
# path, so the checks above cannot pass vacuously on a loader that accepts anything.
assert lib.all
  (
    fixture:
    !(builtins.tryEval (
      import ../features/services/openclaw/plugins.nix {
        inherit lib;
        dir = fixture;
      }
    )).success
  )
  [
    ./fixtures/plugins-unknown-field
    ./fixtures/plugins-bad-contribution
    ./fixtures/plugins-missing-npm
  ];
pkgs.runCommand "openclaw-feature-check"
  {
    nativeBuildInputs = [ (pkgs.python3.withPackages (ps: [ ps.pyyaml ])) ];
  }
  ''
    set -euo pipefail
    python3 ${./openclaw-feature.py} \
      ${openclaw.gateway} ${pluginIds} ${config} \
      ${toString ports.apps} ${toString ports.browserControl} > feature.txt

    # The binary is the only witness that OpenClaw itself discovers the bundled extensions; reading
    # the files back would only repeat what this build wrote.
    python3 ${./openclaw-plugins-loaded.py} \
      ${openclaw.package}/bin/openclaw ${config} ${pluginIds} > plugins.txt

    cat feature.txt plugins.txt > "$out"
  ''
