"""Run the packaged Authentik importer against an isolated, disposable PostgreSQL database."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile

ak, postgres, blueprints, verifier, expectations, measurement = sys.argv[1:]
# Nix sets NIX_BUILD_TOP inside the sandbox; otherwise the platform default temp root is used. `None`
# means TemporaryDirectory picks it, so no machine-specific path is baked in.
scratch = os.environ.get("NIX_BUILD_TOP")
with tempfile.TemporaryDirectory(prefix="directory-", dir=scratch) as directory:
    root = Path(directory)
    root.chmod(0o700)
    socket = root / "socket"
    socket.mkdir(mode=0o700)
    empty_blueprints = root / "empty-blueprints"
    empty_blueprints.mkdir()
    env = {
        "PATH": os.environ["PATH"], "HOME": directory, "TMPDIR": directory,
        "LANG": "C.UTF-8", "PYTHONDONTWRITEBYTECODE": "1",
        "AUTHENTIK_SECRET_KEY": "disposable-directory-qualification-key",
        "AUTHENTIK_POSTGRESQL__HOST": str(socket), "AUTHENTIK_POSTGRESQL__PORT": "25432",
        "AUTHENTIK_POSTGRESQL__USER": "fixture", "AUTHENTIK_POSTGRESQL__NAME": "directory_fixture",
        "AUTHENTIK_BLUEPRINTS_DIR": str(empty_blueprints),
        "AUTHENTIK_ERROR_REPORTING__ENABLED": "false",
        "AUTHENTIK_DISABLE_UPDATE_CHECK": "true",
        "AUTHENTIK_LOG_LEVEL": "warning",
    }
    def run(args, **kwargs):
        return subprocess.run(args, env=env, check=True, timeout=600, **kwargs)

    run([f"{postgres}/initdb", "-D", str(root / "data"), "-U", "fixture",
         "--auth=trust", "--no-locale", "-E", "UTF8"], stdout=subprocess.DEVNULL)
    run([f"{postgres}/pg_ctl", "-D", str(root / "data"), "-l", str(root / "postgres.log"),
         "-o", f"-k {socket} -h '' -p 25432", "-w", "start"], stdout=subprocess.DEVNULL)
    try:
        psql = [f"{postgres}/psql", "-h", str(socket), "-p", "25432", "-U", "fixture", "-v", "ON_ERROR_STOP=1"]
        run(psql + ["-d", "postgres", "-c", "CREATE DATABASE directory_fixture"], stdout=subprocess.DEVNULL)
        # These unmanaged tables are initialized by Authentik's server bootstrap, not Django migrations.
        run(psql + ["-d", "directory_fixture", "-c", """
            CREATE TABLE authentik_install_id (id text NOT NULL);
            INSERT INTO authentik_install_id VALUES ('disposable-fixture');
            CREATE TABLE authentik_version_history (
                id bigserial PRIMARY KEY, timestamp timestamptz NOT NULL,
                version text NOT NULL, build text NOT NULL
            );
        """], stdout=subprocess.DEVNULL)
        with (root / "migrate.log").open("w+") as log:
            try:
                run([ak, "migrate", "--noinput"], stdout=log)
            except subprocess.CalledProcessError:
                log.seek(0)
                print(log.read(), file=sys.stderr)
                raise
        env["AUTHENTIK_BLUEPRINTS_DIR"] = blueprints
        def measure(*extra):
            arguments = [measurement, blueprints, verifier, expectations, str(root / "snapshot.json"), *extra]
            command = f"import runpy, sys; sys.argv = {arguments!r}; runpy.run_path({measurement!r}, run_name='__main__')"
            run([ak, "shell", "-c", command])

        measure()
        backup = str(root / "directory.dump")
        connection = ["-h", str(socket), "-p", "25432", "-U", "fixture"]
        run([f"{postgres}/pg_dump", *connection, "-d", "directory_fixture", "-Fc", "-f", backup])
        run(psql + ["-d", "postgres", "-c", "CREATE DATABASE directory_restored"], stdout=subprocess.DEVNULL)
        run([f"{postgres}/pg_restore", *connection, "-d", "directory_restored", "--exit-on-error", backup])
        env["AUTHENTIK_POSTGRESQL__NAME"] = "directory_restored"
        measure("--restore")
    finally:
        run([f"{postgres}/pg_ctl", "-D", str(root / "data"), "-m", "immediate", "-w", "stop"],
            stdout=subprocess.DEVNULL)
