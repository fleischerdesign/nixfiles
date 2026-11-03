# A restart must not overwrite the user's selected instance, an offline remote server must stay
# listed, and the desktop must declare its tray lifecycle. The failures this catches: the old adapter
# wrote the registry's default into `desktopDefaultHostId` on every start and skipped an unreachable
# host, and an adapter that forgets `desktopMinimizeToTrayEnabled` makes closing the window quit the
# only engine instead of hiding it to the tray.
{
  pkgs,
  ...
}:
pkgs.runCommandLocal "openchamber-provision-defaults-check"
  {
    nativeBuildInputs = [ pkgs.nodejs_22 ];
  }
  ''
    set -eu
    work="$TMPDIR/work"
    mkdir -p "$work/cfg/openchamber" "$work/state" "$work/ud"

    cat > "$work/reg.json" <<'EOF'
    {"hosts":[{"id":"cld-ops-01","label":"cld-ops-01","url":"http://127.0.0.1:1","apiUrl":"http://127.0.0.1:1","mintCommand":"exit 9"}],"defaultHostId":"cld-ops-01"}
    EOF
    cat > "$work/cfg/openchamber/settings.json" <<'EOF'
    {"theme":"dark","desktopDefaultHostId":"local","desktopInitialHostChoiceCompleted":true,"desktopHosts":[{"id":"manual","label":"manual","url":"https://example.invalid"}]}
    EOF

    rc=0
    node ${../features/dev/openchamber/provision.mjs} \
      --registry "$work/reg.json" \
      --state "$work/state/state.json" \
      --settings "$work/cfg/openchamber/settings.json" \
      --app-user-data "$work/ud" || rc=$?
    if [ "$rc" -ne 5 ]; then
      echo "expected exit 5 for an unreachable remote host, got $rc" >&2
      exit 1
    fi

    node - "$work/cfg/openchamber/settings.json" <<'EOF'
    const fs = require('node:fs');
    const settings = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
    const fail = (message) => { console.error(message); process.exit(1); };
    if (settings.desktopDefaultHostId !== 'local') {
      fail('user default was overwritten: ' + settings.desktopDefaultHostId);
    }
    if (settings.desktopInitialHostChoiceCompleted !== true) {
      fail('initial host choice flag was rewritten');
    }
    if (settings.desktopMinimizeToTrayEnabled !== true) {
      fail('close-to-tray lifecycle is not declared');
    }
    if (settings.theme !== 'dark') fail('unmanaged settings key was dropped');
    const ids = (settings.desktopHosts || []).map((host) => host.id);
    if (!ids.includes('manual')) fail('unmanaged host was dropped');
    const central = (settings.desktopHosts || []).find((host) => host.id === 'cld-ops-01');
    if (!central) fail('configured but unreachable server was not listed');
    if (central.clientToken) fail('unreachable server received a token');
    EOF

    # A default that points at a managed entry removed by this run is repaired; an absent default
    # stays absent so upstream opens Local.
    printf '%s' '{"hosts":[]}' > "$work/reg-empty.json"
    printf '%s' '{"previousManaged":["old-host"]}' > "$work/state/state.json"
    printf '%s' '{"desktopDefaultHostId":"old-host","desktopHosts":[{"id":"old-host","label":"old","url":"http://127.0.0.1:1"}]}' > "$work/cfg/openchamber/settings.json"
    node ${../features/dev/openchamber/provision.mjs} \
      --registry "$work/reg-empty.json" \
      --state "$work/state/state.json" \
      --settings "$work/cfg/openchamber/settings.json" \
      --app-user-data "$work/ud"

    node - "$work/cfg/openchamber/settings.json" <<'EOF'
    const fs = require('node:fs');
    const settings = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
    if (settings.desktopDefaultHostId !== undefined) {
      console.error('removed managed default survived: ' + settings.desktopDefaultHostId);
      process.exit(1);
    }
    if ((settings.desktopHosts || []).length !== 0) {
      console.error('removed managed host survived');
      process.exit(1);
    }
    EOF

    touch $out
  ''
