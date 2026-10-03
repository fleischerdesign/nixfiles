# The OpenClaw feature's derived values, measured rather than asserted in prose.
#
# Measure generated listener/model policies and the upstream plugin consumer. Discovery alone is
# insufficient: runtime inspection must also confirm successful registration of plugin capabilities.
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
  runtimeFixture =
    (import ../features/services/openclaw/runtime.nix { inherit lib pkgs inputs; }).build
      {
        id = "openclaw-runtime-fixture";
        stateDir = "/build/runtime-fixture";
        configPath = "/build/runtime-fixture/config.json";
        package = openclaw.package;
        runtime = {
          environment = { };
          credentialFiles.SYNTHETIC_CREDENTIAL = "/build/runtime-fixture/credential";
          packages = [ ];
        };
        settings = { };
      };
  feature = host.config.my.features.services.openclaw;
  # Every instance the host actually provisions, not every profile that exists.
  instances = lib.attrValues feature.instances;
  pluginIds = lib.concatStringsSep "," (
    lib.unique (lib.concatMap (instance: instance.runtimePlugins) instances)
  );
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
    let
      app =
        self.nixosConfigurations.${name}.config.home-manager.users.philipp.my.features.desktop.webapps.apps.ai;
    in
    app.displayName == "OpenClaw"
    && app.url == host.config.my.contracts.provides.openclaw-philipp.publications.web.publicUrl
    && app.wmClass == "openclaw"
    && app.browser == "chrome"
    && !app.isolated
  )
  [
    "hom-wrk-01"
    "mob-nb-01"
  ];
assert lib.all (
  system:
  !(system.config.my.contracts.provides ? open-webui)
  && !(system.config.services.open-webui.enable or false)
) (lib.attrValues self.nixosConfigurations);
# Home Manager escapes account names in unit identifiers; a guessed unit can build but fail startup.
assert lib.all (
  instance:
  let
    service = host.config.systemd.services."openclaw-${instance.owner}";
  in
  lib.all (
    unit: lib.hasAttr (lib.removeSuffix ".service" unit) host.config.systemd.services
  ) service.requires
) instances;
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
assert lib.all (
  instance: lib.all (name: lib.hasAttr name openclaw.runtimePlugins) instance.runtimePlugins
) (lib.attrValues feature.users);
pkgs.runCommand "openclaw-feature-check"
  {
    nativeBuildInputs = [
      (pkgs.python3.withPackages (ps: [ ps.pyyaml ]))
      pkgs.nodejs
    ];
  }
  ''
    set -euo pipefail
    mkdir -p /build/runtime-fixture
    cp ${runtimeFixture.source} /build/runtime-fixture/config.json
    printf '%s' 'synthetic credential' > /build/runtime-fixture/credential
    ${runtimeFixture.execute}/bin/openclaw-runtime-fixture-exec python3 -c '
    import os
    assert os.environ["OPENCLAW_CONFIG_PATH"] == "/build/runtime-fixture/config.json"
    assert os.environ["OPENCLAW_STATE_DIR"] == "/build/runtime-fixture"
    assert os.environ["SYNTHETIC_CREDENTIAL"] == "synthetic credential"
    print("Expected literal runtime paths and file-backed credentials: verified")
    ' > runtime-environment.txt
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

    # Runtime registration is the consumer-visible witness, not the package layout alone.
    python3 ${./openclaw-plugins-loaded.py} \
      ${openclaw.package}/bin/openclaw ${config} ${pluginIds} > plugins.txt

    cat feature.txt plugins.txt device-auth.txt node-capabilities.txt runtime-environment.txt > "$out"
  ''
