# Catch Nix packaging that drops Fleet modules or ships an invalid OpenChamber extension manifest.
{
  pkgs,
  inputs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  extension = import ../features/dev/openchamber/fleet-extension.nix { inherit pkgs inputs; };
  app = "${inputs.openchamber.packages.${system}.openchamber.passthru.core}/lib/openchamber";
in
pkgs.runCommand "openchamber-fleet-check"
  {
    nativeBuildInputs = [ pkgs.nodejs_22 ];
  }
  ''
    root="$TMPDIR/fleet-extension"
    mkdir -p "$root"
    cp -r ${extension} "$root/fleet"
    cat > "$root/registry.json" <<'JSON'
    {"version":1,"extensions":[{"id":"openchamber-builtin-fleet","directory":"fleet"}]}
    JSON

    node ${../features/dev/openchamber/validate-plugins.mjs} ${app} "$root"

    PLUGIN="$root/fleet/plugin/dist/plugin/index.js" node --input-type=module - <<'JS'
    const { default: plugin } = await import(process.env.PLUGIN)
    const tools = []
    const cleanup = await plugin.setup({
      location: { directory: process.cwd() },
      tool: { transform: async (edit) => edit({ add: (tool) => tools.push(tool) }) },
      session: {
        get: async () => ({ location: { directory: process.cwd() } }),
        synthetic: async () => ({}),
      },
    })
    const names = tools.map((tool) => tool.name).sort()
    const expected = ['fleet_exec', 'fleet_fetch', 'fleet_job_cancel', 'fleet_job_status', 'fleet_recover', 'fleet_status', 'fleet_sync']
    if (JSON.stringify(names) !== JSON.stringify(expected)) {
      throw new Error('Fleet plugin tools mismatch: ' + names.join(', '))
    }
    await cleanup()
    JS

    echo "Fleet extension inspector and packaged OpenCode plugin passed" > "$out"
  ''
