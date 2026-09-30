"""Exercise delivered OIDC policy, Vaultwarden, PostgreSQL and snapshot failure paths."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
from types import SimpleNamespace
from urllib.error import URLError
from urllib.request import urlopen

import yaml


class Loader(yaml.SafeLoader):
    pass


def tag(loader, name, node):
    if isinstance(node, yaml.SequenceNode):
        value = loader.construct_sequence(node)
    else:
        value = loader.construct_scalar(node)
    return {"tag": name, "value": value}


Loader.add_multi_constructor("!", tag)


def expression(source, user):
    namespace = {}
    exec("def evaluate(request):\n" + "\n".join("    " + line for line in source.splitlines()), namespace)
    return namespace["evaluate"](SimpleNamespace(user=user))


def check_blueprints(directory, settings):
    document = yaml.load((directory / "03-apps/oidc-apps-generated.yaml").read_text(), Loader=Loader)
    entries = document["entries"]
    policy = next(e for e in entries if e.get("identifiers", {}).get("name") == "vaultwarden-authenticated-humans")
    for authenticated, active, kind, expected in [
        (True, True, "internal", True),
        (True, True, "external", True),
        (True, True, "service_account", False),
        (False, True, "internal", False),
        (True, False, "internal", False),
    ]:
        user = SimpleNamespace(is_authenticated=authenticated, is_active=active, type=kind)
        assert expression(policy["attrs"]["expression"], user) is expected, "human audience policy failed"
    binding = next(e for e in entries if e.get("identifiers", {}).get("policy") == {"tag": "KeyOf", "value": policy["id"]})
    assert binding["attrs"]["enabled"] and not binding["attrs"]["negate"]
    provider = next(e for e in entries if e.get("identifiers", {}).get("name") == "Provider for Vaultwarden")
    attrs = provider["attrs"]
    assert attrs["client_id"] == settings["SSO_CLIENT_ID"]
    assert attrs["access_token_validity"] == "minutes=15"
    assert attrs["sub_mode"] == "hashed_user_id"
    assert attrs["redirect_uris"] == [{"matching_mode": "strict", "url": settings["DOMAIN"] + "/identity/connect/oidc-signin"}]
    assert attrs["client_secret"] == {"tag": "Env", "value": "AUTHENTIK_OIDC_VAULTWARDEN_SECRET"}
    assert any("scope-offline_access" in str(mapping) for mapping in attrs["property_mappings"])
    assert not any("scope-email" in str(mapping) for mapping in attrs["property_mappings"])
    mapping = next(e for e in entries if e.get("id") == "scope_vaultwarden_email")
    assert expression(mapping["attrs"]["expression"], SimpleNamespace(email="person@example.test")) == {"email": "person@example.test"}
    assert "scope_vaultwarden_email" in str(attrs["property_mappings"])


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def wait_alive(process, url, log):
    deadline = time.monotonic() + 60
    while process.poll() is None and time.monotonic() < deadline:
        try:
            with urlopen(url, timeout=1) as response:
                assert response.status == 200
                return
        except (URLError, TimeoutError):
            time.sleep(0.2)
    raise AssertionError("Vaultwarden did not become healthy:\n" + log.read_text())


def check_runtime(settings, executable, snapshot_source):
    root = Path.cwd()
    socket = root / "socket"
    socket.mkdir()
    env = os.environ | {"PGHOST": str(socket), "PGDATABASE": "postgres"}
    run("initdb", "-D", "pgdata", "--auth-local=trust", "--auth-host=reject", env=env)
    run("pg_ctl", "-D", "pgdata", "-l", "postgres.log", "-o", f"-h '' -k {socket}", "-w", "start", env=env)
    process = None
    try:
        run("psql", "-v", "ON_ERROR_STOP=1", "-c", "CREATE ROLE vaultwarden LOGIN;", env=env)
        run("createdb", "--owner=vaultwarden", "vaultwarden", env=env)
        data = root / "data"
        data.mkdir()
        environment = env | {key: str(value).lower() if isinstance(value, bool) else str(value) for key, value in settings.items()}
        environment |= {
            "DATA_FOLDER": str(data),
            "DATABASE_URL": f"postgresql:///vaultwarden?host={socket}&user=vaultwarden",
            "SSO_CLIENT_SECRET": "isolated-test-secret-not-a-production-credential",
            "ROCKET_PORT": "18082",
        }
        log_path = root / "vaultwarden.log"
        with log_path.open("w") as log:
            process = subprocess.Popen([executable], env=environment, stdout=log, stderr=subprocess.STDOUT)
        wait_alive(process, "http://127.0.0.1:18082/alive", log_path)
        with urlopen("http://127.0.0.1:18082/admin", timeout=5) as response:
            assert "admin panel is disabled" in response.read().decode().lower()
        with urlopen("http://127.0.0.1:18082/api/config", timeout=5) as response:
            configuration = json.load(response)
            assert configuration["environment"]["vault"] == settings["DOMAIN"]
        process.terminate()
        process.wait(timeout=20)
        process = None

        run("psql", "--username=vaultwarden", "--dbname=vaultwarden", "-v", "ON_ERROR_STOP=1", "-c", "CREATE TABLE restore_probe(value text); INSERT INTO restore_probe VALUES ('must survive');", env=env)
        (data / "attachments").mkdir()
        (data / "attachments/example").write_text("encrypted-attachment-fixture")
        (data / "icon_cache").mkdir()
        (data / "icon_cache/regenerable").write_text("cache")
        mocks = root / "mocks"
        mocks.mkdir()
        shell = shutil.which("bash")
        assert shell is not None, "test shell is missing"
        (mocks / "systemctl").write_text("#!" + shell + '''
set -euo pipefail
echo "$1" >> "$COMMAND_LOG"
if [ "$1" = start ] && [ "${FAIL_START:-0}" = 1 ]; then exit 1; fi
''')
        (mocks / "runuser").write_text("#!" + shell + '''
set -euo pipefail
test "$1" = -u && test "$2" = vaultwarden && test "$3" = --
if [ "${FAIL_DUMP:-0}" = 1 ]; then exit 1; fi
shift 3
exec "$@"
''')
        for mock in mocks.iterdir():
            mock.chmod(0o700)
        command_log = root / "commands.log"
        snapshot_env = env | {"PATH": str(mocks) + ":" + os.environ["PATH"], "COMMAND_LOG": str(command_log), "PGUSER": "vaultwarden"}
        snapshot_dir = root / "snapshots"
        command = ["bash", str(snapshot_source), str(data), str(snapshot_dir), "vaultwarden", "vaultwarden", str(socket)]
        run(*command, env=snapshot_env)
        assert command_log.read_text().splitlines() == ["is-active", "stop", "start", "is-active"]
        assert (snapshot_dir / "current/data/attachments/example").read_text() == "encrypted-attachment-fixture"
        assert not (snapshot_dir / "current/data/icon_cache").exists()
        run("createdb", "--owner=vaultwarden", "restored", env=env)
        run("pg_restore", "--dbname=restored", "--exit-on-error", str(snapshot_dir / "current/database.dump"), env=env)
        result = run("psql", "--dbname=restored", "-Atc", "SELECT value FROM restore_probe", capture_output=True, env=env)
        assert result.stdout.strip() == "must survive", "database restore lost data"
        for flag in ["FAIL_DUMP", "FAIL_START"]:
            command_log.write_text("")
            result = subprocess.run(command, env=snapshot_env | {flag: "1"})
            assert result.returncode != 0, f"{flag}: failure was hidden"
            assert "start" in command_log.read_text().splitlines(), f"{flag}: no restart attempted"
            assert (snapshot_dir / "current/data/attachments/example").exists(), "failed prepare lost the previous artifact"
    finally:
        if process is not None:
            process.terminate()
            process.wait(timeout=20)
        run("pg_ctl", "-D", "pgdata", "-m", "immediate", "-w", "stop", env=env)


if __name__ == "__main__":
    blueprint_dir, settings_file, executable, snapshot_source = sys.argv[1:]
    settings = json.loads(Path(settings_file).read_text())
    # The shared projection intentionally overwrites forwarded headers. Caddy calls
    # these redundant; every other warning means this test did not validate cleanly.
    warnings = Path("caddy.log").read_text().splitlines()
    assert len(warnings) == 3 and all(
        "Unnecessary header_up " + header + ":" in line
        for header, line in zip(["X-Forwarded-For", "X-Forwarded-Proto", "X-Forwarded-Host"], warnings)
    ), "unexpected Caddy verdict: " + "\n".join(warnings)
    check_blueprints(Path(blueprint_dir), settings)
    check_runtime(settings, executable, Path(snapshot_source))
    print("Vaultwarden: OIDC policy, runtime, database/file restore and backup negative controls passed")
