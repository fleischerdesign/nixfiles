# Catch Fleet being embedded in the OpenChamber core again, a broken portable extension, or an
# installer regression. Fleet is a runtime extension: the app's built-in registry must stay clean.
{
  pkgs,
  inputs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  extension = inputs.openchamber-fleet.packages.${system}.extension;
  app = "${inputs.openchamber.packages.${system}.openchamber.passthru.core}/lib/openchamber";
  installer = ../features/dev/openchamber/fleet_install.py;
  installerTest = ../features/dev/openchamber/fleet_install_test.py;
in
pkgs.runCommand "openchamber-fleet-check"
  {
    nativeBuildInputs = [
      pkgs.nodejs_22
      pkgs.python3
    ];
  }
  ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"

    builtins="$TMPDIR/builtins"
    mkdir -p "$builtins"
    registry="${app}/packages/web/build/server/built-in-extensions/registry.json"
    if [ ! -f "$registry" ]; then
      echo "OpenChamber built-in registry is missing: $registry" >&2
      exit 1
    fi
    cp "$registry" "$builtins/registry.json"
    python3 - "$builtins/registry.json" <<'PY'
    import json
    import sys

    registry = json.load(open(sys.argv[1], encoding='utf-8'))
    entries = registry.get('extensions', [])
    if any(entry.get('id') == 'openchamber-builtin-fleet' or entry.get('directory') == 'fleet' for entry in entries):
        raise SystemExit(
            'Fleet must be a runtime extension; it must not be copied into the OpenChamber core'
        )
    PY

    cp -r ${extension} "$TMPDIR/extension"
    chmod -R u+w "$TMPDIR/extension"
    EXT="$TMPDIR/extension" PLUGIN="$TMPDIR/extension/plugin/dist/plugin/index.js" APP="${app}" \
      node --input-type=module - <<'JS'
    import fs from 'node:fs';

    const manifest = JSON.parse(fs.readFileSync(process.env.EXT + '/package.json', 'utf8'));
    if (manifest.openchamber?.id !== 'openchamber-fleet') {
      throw new Error(`portable extension id is ''${manifest.openchamber?.id}, expected openchamber-fleet`);
    }
    const { parseManifestJson } = await import(process.env.APP + '/packages/sdk/dist/schemas.js');
    const parsed = parseManifestJson(JSON.stringify(manifest));
    if (!parsed.ok) throw new Error(parsed.message);
    const panel = parsed.manifest.contributes.panel;
    if (panel.id !== 'openchamber-fleet') {
      throw new Error(`parsed panel id is ''${panel.id}, expected openchamber-fleet`);
    }
    if (parsed.manifest.contributes.opencodePlugin !== 'plugin') {
      throw new Error('portable extension does not contribute the OpenCode plugin');
    }
    if (!parsed.manifest.contributes.service) {
      throw new Error('portable extension does not contribute the local service');
    }

    const { default: plugin } = await import(process.env.PLUGIN);
    const tools = [];
    const cleanup = await plugin.setup({
      location: { directory: process.env.HOME },
      tool: { transform: async (edit) => edit({ add: (tool) => tools.push(tool) }) },
      session: {
        get: async () => ({ location: { directory: process.env.HOME } }),
        synthetic: async () => ({}),
      },
    });
    const names = tools.map((tool) => tool.name).sort();
    const expected = [
      'fleet_exec',
      'fleet_fetch',
      'fleet_hosts',
      'fleet_job_cancel',
      'fleet_job_status',
      'fleet_jobs',
      'fleet_recover',
      'fleet_run',
      'fleet_status',
      'fleet_sync',
    ];
    if (JSON.stringify(names) !== JSON.stringify(expected)) {
      throw new Error('Fleet plugin tools mismatch: ' + names.join(', '));
    }
    await cleanup();
    JS

    python3 ${installerTest} ${installer}

    echo "Fleet runtime extension and installer passed; the OpenChamber core stays free of Fleet" > "$out"
  ''
