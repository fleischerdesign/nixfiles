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
  nodeConfigs =
    map
      (
        name:
        let
          nodeHost = self.nixosConfigurations.${name}.config;
          node = lib.head (lib.attrValues nodeHost.my.features.services.openclaw.nodes);
          id = "openclaw-node-${node.gateway}-${node.instance}-${nodeHost.my.user.primary}";
        in
        nodeHost.environment.etc."openclaw/${id}.json".source
      )
      [
        "hom-wrk-01"
        "mob-nb-01"
      ];
in
assert feature.enable;
assert instances != [ ];
assert lib.all
  (
    name:
    lib.all (
      node:
      !(node.credentialFiles ? OPENCLAW_GATEWAY_PASSWORD)
      && !(node.credentialFiles ? OPENCLAW_GATEWAY_TOKEN)
      && !(node.settings ? gateway.remote.password)
      && !(node.settings ? gateway.remote.token)
    ) (lib.attrValues self.nixosConfigurations.${name}.config.my.features.services.openclaw.nodes)
  )
  [
    "hom-wrk-01"
    "mob-nb-01"
  ];
assert lib.all
  (
    name:
    lib.all (
      node:
      lib.all (package: lib.elem package node.packages) [
        pkgs.ffmpeg
        pkgs.libnotify
      ]
    ) (lib.attrValues self.nixosConfigurations.${name}.config.my.features.services.openclaw.nodes)
  )
  [
    "hom-wrk-01"
    "mob-nb-01"
  ];
assert lib.all (
  instance:
  let
    publication = host.config.my.contracts.provides."openclaw-${instance.owner}".publications.web;
  in
  publication.auth == "authentik"
  &&
    publication.unauthenticatedPaths == [
      "/j/*"
      "/__openclaw__/worker"
    ]
  && publication.machineClientsBypassAuth
) instances;
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
    nativeBuildInputs = [
      (pkgs.python3.withPackages (ps: [ ps.pyyaml ]))
      pkgs.nodejs
    ];
  }
  ''
    set -euo pipefail
    node ${./openclaw-device-auth.mjs} ${openclaw.gateway} > device-auth.txt
    node ${./openclaw-node-capabilities.mjs} ${openclaw.gateway} \
      ${lib.escapeShellArgs (map toString nodeConfigs)} \
      ${
        lib.escapeShellArg (
          lib.makeBinPath [
            pkgs.ffmpeg
            pkgs.libnotify
          ]
        )
      } > node-capabilities.txt
    python3 ${./openclaw-feature.py} \
      ${openclaw.gateway} ${pluginIds} ${config} \
      ${toString ports.apps} ${toString ports.browserControl} > feature.txt

    # The binary is the only witness that OpenClaw itself discovers the bundled extensions; reading
    # the files back would only repeat what this build wrote.
    python3 ${./openclaw-plugins-loaded.py} \
      ${openclaw.package}/bin/openclaw ${config} ${pluginIds} > plugins.txt

    cat feature.txt plugins.txt device-auth.txt node-capabilities.txt > "$out"
  ''
