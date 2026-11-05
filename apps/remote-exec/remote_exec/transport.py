"""Byte transport, executor identity and process supervision.

Identity is inventory plus a pinned SSH host key plus an approved non-root
account: the SSH executor identity is not the native pairing identity. The tool
creates no credential, account or directory; the executor module declares them.

`SshTransport` runs attempt supervision through the executor's own user systemd
manager (`systemd-run --user`), so an SSH disconnect does not kill the attempt
and a stop kills the unit's whole cgroup. `LocalTransport` runs the same runner
in the foreground and exists only for the fixture suite; its timeout says
nothing about SSH transport behaviour.
"""

from __future__ import annotations

import base64
import json
import os
import re
import shlex
import shutil
import subprocess
import tempfile


class TransportError(Exception):
    pass


def cleanup(path: str) -> None:
    """Remove a capture directory this process created."""
    shutil.rmtree(path, ignore_errors=True)


SSH_OPTIONS = [
    "-o",
    "BatchMode=yes",
    "-o",
    "StrictHostKeyChecking=yes",
    "-o",
    "ConnectTimeout=10",
    "-o",
    "ServerAliveInterval=15",
    "-o",
    "ServerAliveCountMax=3",
    "-o",
    "GlobalKnownHostsFile=/dev/null",
]


def _b64(value: object) -> str:
    return base64.b64encode(json.dumps(value).encode("utf-8")).decode("ascii")


class Transport:
    supervised = False

    def run_py(self, code: str, args: object, timeout: float | None = None) -> subprocess.CompletedProcess:
        raise NotImplementedError

    def push_tree(self, source: str, destination: str) -> None:
        raise NotImplementedError

    def pull_tree(self, source: str, destination: str) -> None:
        raise NotImplementedError

    def pull_paths(self, source: str, destination: str, paths: list[str]) -> None:
        raise NotImplementedError

    def push_paths(self, source: str, destination: str, paths: list[str]) -> dict:
        raise NotImplementedError

    def preflight(self, root: str) -> dict:
        raise NotImplementedError

    def supervise(
        self, attempt_dir: str, timeout: int, unit: str | None = None, work_dir: str | None = None,
        runtime_max_secs: int | None = None,
    ) -> None:
        raise NotImplementedError

    def cancel(self, unit: str) -> dict:
        raise NotImplementedError


def _rsync_base() -> list[str]:
    return ["rsync", "-a", "--no-owner", "--no-group", "--protect-args"]


def _rsync_stats(output: bytes, path_count: int) -> dict:
    size = re.search(rb"Total transferred file size: ([\d,]+) bytes", output)
    files = re.search(rb"Number of regular files transferred: ([\d,]+)", output)
    return {
        "paths": path_count,
        "files": int(files.group(1).replace(b",", b"")) if files else 0,
        "bytes": int(size.group(1).replace(b",", b"")) if size else 0,
    }


class LocalTransport(Transport):
    def _command(self) -> list[str]:
        return ["python3", "-"]

    def run_py(self, code: str, args: object, timeout: float | None = None) -> subprocess.CompletedProcess:
        return subprocess.run(
            self._command() + [_b64(args)],
            input=code.encode("utf-8"),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            check=False,
        )

    def _rsync(self, source: str, destination: str, extra: list[str] | None = None) -> None:
        os.makedirs(destination, exist_ok=True)
        argv = _rsync_base() + (extra or []) + [source.rstrip("/") + "/", destination.rstrip("/") + "/"]
        process = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
        if process.returncode != 0:
            raise TransportError(process.stderr.decode("utf-8", "replace").strip())

    def push_tree(self, source: str, destination: str) -> None:
        self._rsync(source, destination)

    def pull_tree(self, source: str, destination: str) -> None:
        self._rsync(source, destination)

    def pull_paths(self, source: str, destination: str, paths: list[str]) -> None:
        os.makedirs(destination, exist_ok=True)
        listfile = tempfile.NamedTemporaryFile("wb", delete=False)
        try:
            for path in paths:
                listfile.write(path.encode("utf-8", "surrogateescape") + b"\0")
            listfile.close()
            process = subprocess.run(
                _rsync_base()
                + ["--from0", f"--files-from={listfile.name}", source.rstrip("/") + "/", destination.rstrip("/") + "/"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            if process.returncode != 0:
                raise TransportError(process.stderr.decode("utf-8", "replace").strip())
        finally:
            os.unlink(listfile.name)

    def push_paths(self, source: str, destination: str, paths: list[str]) -> dict:
        if not paths:
            return {"paths": 0, "files": 0, "bytes": 0}
        os.makedirs(destination, exist_ok=True)
        listfile = tempfile.NamedTemporaryFile("wb", delete=False)
        try:
            for path in paths:
                listfile.write(path.encode("utf-8", "surrogateescape") + b"\0")
            listfile.close()
            process = subprocess.run(
                _rsync_base()
                + [
                    "--from0",
                    f"--files-from={listfile.name}",
                    "--stats",
                    source.rstrip("/") + "/",
                    destination.rstrip("/") + "/",
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
                env=dict(os.environ, LC_ALL="C"),
            )
            if process.returncode != 0:
                raise TransportError(process.stderr.decode("utf-8", "replace").strip())
            return _rsync_stats(process.stdout, len(paths))
        finally:
            os.unlink(listfile.name)

    def preflight(self, root: str) -> dict:
        for command in ("python3", "rsync", "git"):
            if shutil.which(command) is None:
                raise TransportError(f"{command} is not available on the executor")
        import pwd

        real = os.path.realpath(root)
        if real != os.path.abspath(root):
            raise TransportError(f"declared root {root} resolves to {real}")
        if not os.path.isdir(real):
            raise TransportError(f"declared root {real} does not exist")
        info = os.stat(real)
        uid = os.getuid()
        if uid == 0:
            raise TransportError("the local fixture transport refuses to run as root")
        if info.st_uid != uid:
            raise TransportError(f"declared root {real} is not owned by uid {uid}")
        if not os.access(real, os.W_OK):
            raise TransportError(f"declared root {real} is not writable by uid {uid}")
        return {
            "hostname": os.uname().nodename,
            "machine": os.uname().machine,
            "user": pwd.getpwuid(uid).pw_name,
            "uid": uid,
            "root": real,
            "path": os.environ.get("PATH", ""),
        }

    def supervise(
        self, attempt_dir: str, timeout: int, unit: str | None = None, work_dir: str | None = None,
        runtime_max_secs: int | None = None,
    ) -> None:
        process = subprocess.run(
            ["python3", os.path.join(attempt_dir, "runner.py"), os.path.join(attempt_dir, "runner-config.json")],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout + 60,
            check=False,
        )
        if process.returncode not in (0, 3):
            raise TransportError(process.stderr.decode("utf-8", "replace").strip())

    def cancel(self, unit: str) -> dict:
        return {"unit": unit, "ActiveState": "inactive", "Result": "not-supported-locally"}


class SshTransport(Transport):
    supervised = True

    def __init__(self, user: str, address: str, host_key: str, identity: str):
        self.user = user
        self.address = address
        self.host_key = host_key
        self.identity = identity
        self.target = f"{user}@{address}"
        self._known_hosts = tempfile.NamedTemporaryFile("w", delete=False)
        # Port 22 is OpenSSH's default, so the lookup key is the bare host;
        # a bracketed `[host]:22` entry would not match it.
        self._known_hosts.write(f"{address} {host_key}\n")
        self._known_hosts.close()
        self._ssh = [
            "ssh",
            *SSH_OPTIONS,
            "-o",
            f"UserKnownHostsFile={self._known_hosts.name}",
            "-i",
            identity,
            "-o",
            "IdentitiesOnly=yes",
        ]

    def close(self) -> None:
        try:
            os.unlink(self._known_hosts.name)
        except OSError:
            pass

    def run_py(self, code: str, args: object, timeout: float | None = None) -> subprocess.CompletedProcess:
        return subprocess.run(
            [*self._ssh, self.target, "python3", "-", _b64(args)],
            input=code.encode("utf-8"),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            check=False,
        )

    def _rsync(self, source: str, destination: str, pull: bool, extra: list[str] | None = None) -> None:
        ssh = shlex.join(self._ssh)
        if pull:
            remote = f"{self.target}:{source.rstrip('/')}/"
            argv = _rsync_base() + (extra or []) + ["-e", ssh, remote, destination.rstrip("/") + "/"]
        else:
            remote = f"{self.target}:{destination.rstrip('/')}/"
            argv = _rsync_base() + (extra or []) + ["-e", ssh, source.rstrip("/") + "/", remote]
        process = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
        if process.returncode != 0:
            raise TransportError(process.stderr.decode("utf-8", "replace").strip())

    def push_tree(self, source: str, destination: str) -> None:
        self._rsync(source, destination, pull=False)

    def pull_tree(self, source: str, destination: str) -> None:
        self._rsync(source, destination, pull=True)

    def pull_paths(self, source: str, destination: str, paths: list[str]) -> None:
        listfile = tempfile.NamedTemporaryFile("wb", delete=False)
        try:
            for path in paths:
                listfile.write(path.encode("utf-8", "surrogateescape") + b"\0")
            listfile.close()
            self._rsync(
                source,
                destination,
                pull=True,
                extra=["--from0", f"--files-from={listfile.name}"],
            )
        finally:
            os.unlink(listfile.name)

    def push_paths(self, source: str, destination: str, paths: list[str]) -> dict:
        if not paths:
            return {"paths": 0, "files": 0, "bytes": 0}
        ssh = shlex.join(self._ssh)
        remote = f"{self.target}:{destination.rstrip('/')}/"
        listfile = tempfile.NamedTemporaryFile("wb", delete=False)
        try:
            for path in paths:
                listfile.write(path.encode("utf-8", "surrogateescape") + b"\0")
            listfile.close()
            argv = _rsync_base() + [
                "--from0",
                f"--files-from={listfile.name}",
                "--stats",
                "-e",
                ssh,
                source.rstrip("/") + "/",
                remote,
            ]
            process = subprocess.run(
                argv,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
                env=dict(os.environ, LC_ALL="C"),
            )
            if process.returncode != 0:
                raise TransportError(process.stderr.decode("utf-8", "replace").strip())
            return _rsync_stats(process.stdout, len(paths))
        finally:
            os.unlink(listfile.name)

    def preflight(self, root: str) -> dict:
        process = self.run_py(
            "import json,os,pwd,shutil,subprocess,sys\n"
            "c=json.loads(__import__('base64').b64decode(sys.argv[1]).decode('utf-8'))\n"
            "uid=os.getuid(); real=os.path.realpath(c['root'])\n"
            "out={'hostname':os.uname().nodename,'machine':os.uname().machine,\n"
            "     'user':pwd.getpwuid(uid).pw_name,'uid':uid,'root':real,\n"
            "     'path':os.environ.get('PATH',''),\n"
            "     'missing':[t for t in ('python3','rsync','git','systemd-run','systemctl') if shutil.which(t) is None],\n"
            "     'rootExists':os.path.isdir(real),\n"
            "     'rootOwner':os.stat(real).st_uid if os.path.isdir(real) else None,\n"
            "     'rootWritable':os.access(real, os.W_OK) if os.path.isdir(real) else False}\n"
            "menv=dict(os.environ, XDG_RUNTIME_DIR='/run/user/%d' % uid,\n"
            "          DBUS_SESSION_BUS_ADDRESS='unix:path=/run/user/%d/bus' % uid)\n"
            "probe=subprocess.run(['systemctl','--user','is-system-running'],env=menv,\n"
            "                     stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)\n"
            "out['userManager']=probe.returncode == 0\n"
            "print(json.dumps(out))\n",
            {"root": root},
            timeout=45,
        )
        if process.returncode != 0:
            raise TransportError(
                "SSH authorization or pinned host identity check failed: "
                + process.stderr.decode("utf-8", "replace").strip()
            )
        return json.loads(process.stdout.decode("utf-8"))

    def supervise(
        self, attempt_dir: str, timeout: int, unit: str | None = None, work_dir: str | None = None,
        runtime_max_secs: int | None = None,
    ) -> None:
        process = self.run_py(
            "import base64,json,os,subprocess,sys\n"
            "c=json.loads(base64.b64decode(sys.argv[1]).decode('utf-8'))\n"
            "uid=os.getuid()\n"
            "env=dict(os.environ)\n"
            "env['XDG_RUNTIME_DIR']='/run/user/%d' % uid\n"
            "env['DBUS_SESSION_BUS_ADDRESS']='unix:path=/run/user/%d/bus' % uid\n"
            "cfg=json.load(open(os.path.join(c['attempt'],'runner-config.json'),'r',encoding='utf-8'))\n"
            "cmd=['systemd-run','--user','--quiet','--collect','--unit='+c['unit'],\n"
            "     '--property=WorkingDirectory='+c['workDir'],\n"
            "     '--property=RuntimeMaxSec=%d' % c['runtimeMax'],\n"
            "     '--property=KillMode=control-group',\n"
            "     '--property=TimeoutStopSec=30',\n"
            "     '--setenv=HOME='+os.path.join(c['attempt'],'home'),\n"
            "     '--setenv=TMPDIR='+os.path.join(c['attempt'],'tmp'),\n"
            "     '--setenv=PATH='+cfg['env'].get('PATH','/run/current-system/sw/bin'),\n"
            "     '--setenv=LANG=C.UTF-8',\n"
            "     '--no-block', sys.executable, os.path.join(c['attempt'],'runner.py'),\n"
            "     os.path.join(c['attempt'],'runner-config.json')]\n"
            "p=subprocess.run(cmd,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)\n"
            "if p.returncode != 0:\n"
            "    sys.stderr.write(p.stderr.decode('utf-8','replace'))\n"
            "    sys.exit(2)\n"
            "for _ in range(40):\n"
            "    q=subprocess.run(['systemctl','--user','is-active',c['unit']],env=env,\n"
            "                     stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)\n"
            "    if q.returncode != 0:\n"
            "        sys.exit(0)\n"
            "    if q.stdout.decode().strip() in ('active','activating','reloading'):\n"
            "        sys.exit(0)\n"
            "    import time; time.sleep(0.25)\n"
            "sys.stderr.write('unit did not become active')\n"
            "sys.exit(2)\n",
            {
                "attempt": attempt_dir,
                "unit": unit,
                "timeout": timeout,
                "runtimeMax": runtime_max_secs or timeout,
                "workDir": work_dir or os.path.join(attempt_dir, "work"),
            },
            timeout=60,
        )
        if process.returncode != 0:
            raise TransportError(
                "attempt supervision did not start: "
                + process.stderr.decode("utf-8", "replace").strip()
            )

    def cancel(self, unit: str) -> dict:
        process = self.run_py(
            "import base64,json,os,subprocess,sys,time\n"
            "c=json.loads(base64.b64decode(sys.argv[1]).decode('utf-8'))\n"
            "uid=os.getuid()\n"
            "env=dict(os.environ)\n"
            "env['XDG_RUNTIME_DIR']='/run/user/%d' % uid\n"
            "env['DBUS_SESSION_BUS_ADDRESS']='unix:path=/run/user/%d/bus' % uid\n"
            "subprocess.run(['systemctl','--user','stop',c['unit']],env=env,check=False)\n"
            "state={}\n"
            "for _ in range(60):\n"
            "    p=subprocess.run(['systemctl','--user','show','-p','ActiveState','-p','SubState','-p','Result',c['unit']],env=env,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)\n"
            "    state={k:v for k,_,v in (line.partition('=') for line in p.stdout.decode().splitlines())}\n"
            "    if state.get('ActiveState') in ('inactive','failed'): break\n"
            "    time.sleep(0.5)\n"
            "print(json.dumps(state))\n",
            {"unit": unit},
            timeout=90,
        )
        if process.returncode != 0:
            raise TransportError(process.stderr.decode("utf-8", "replace").strip())
        return json.loads(process.stdout.decode("utf-8"))
