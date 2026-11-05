"""Byte transport and remote filesystem primitives.

Two transports share one contract:

* `SshTransport` moves bytes with rsync over an authenticated SSH connection.
  Host keys come from the system known-hosts file (inventory-derived, see
  `inventory/ssh.nix`); authorization is a non-root SSH account. No credential
  is created or read by this program.
* `LocalTransport` is the same contract against a local directory. It exists so
  the capture/execute/collect path can be tested without a second machine; it is
  never selected implicitly.

Every remote operation runs a Python script over stdin with base64-encoded JSON
arguments, so a path or file name is never interpolated into a remote shell.
"""

from __future__ import annotations

import base64
import json
import os
import shlex
import shutil
import subprocess


class TransportError(Exception):
    pass


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
]


def _b64(value: object) -> str:
    return base64.b64encode(json.dumps(value).encode("utf-8")).decode("ascii")


class Transport:
    def __init__(self, user: str | None = None, host: str | None = None, identity: str | None = None):
        self.user = user
        self.host = host
        self.identity = identity

    # -- contract ---------------------------------------------------------
    def run_py(self, code: str, args: object, timeout: float | None = None) -> subprocess.CompletedProcess:
        raise NotImplementedError

    def push_tree(self, source: str, destination: str) -> None:
        raise NotImplementedError

    def pull_tree(self, source: str, destination: str) -> None:
        raise NotImplementedError

    def preflight(self) -> dict:
        raise NotImplementedError


class LocalTransport(Transport):
    def __init__(self, root: str | None = None):
        super().__init__()
        self.root = root

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

    def _rsync(self, source: str, destination: str) -> None:
        os.makedirs(destination, exist_ok=True)
        process = subprocess.run(
            [
                "rsync",
                "-a",
                "--no-owner",
                "--no-group",
                "--protect-args",
                source.rstrip("/") + "/",
                destination.rstrip("/") + "/",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        if process.returncode != 0:
            raise TransportError(process.stderr.decode("utf-8", "replace").strip())

    def push_tree(self, source: str, destination: str) -> None:
        self._rsync(source, destination)

    def pull_tree(self, source: str, destination: str) -> None:
        self._rsync(source, destination)

    def preflight(self) -> dict:
        for command in ("python3", "rsync"):
            if shutil.which(command) is None:
                raise TransportError(f"{command} is not available on the executor")
        return {
            "hostname": os.uname().nodename,
            "machine": os.uname().machine,
            "path": os.environ.get("PATH", ""),
        }


class SshTransport(Transport):
    def __init__(self, user: str, host: str, identity: str | None = None):
        super().__init__(user=user, host=host, identity=identity)
        self.target = f"{user}@{host}"
        self._ssh = ["ssh", *SSH_OPTIONS]
        if identity:
            self._ssh += ["-i", identity, "-o", "IdentitiesOnly=yes"]

    def run_py(self, code: str, args: object, timeout: float | None = None) -> subprocess.CompletedProcess:
        return subprocess.run(
            [*self._ssh, self.target, "python3", "-", _b64(args)],
            input=code.encode("utf-8"),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            check=False,
        )

    def _rsync(self, source: str, destination: str, pull: bool) -> None:
        remote = f"{self.target}:{destination.rstrip('/')}/"
        ssh = shlex.join(self._ssh)
        if pull:
            argv = ["rsync", "-a", "--no-owner", "--no-group", "--protect-args", "-e", ssh, remote, destination.rstrip("/") + "/"]
        else:
            argv = ["rsync", "-a", "--no-owner", "--no-group", "--protect-args", "-e", ssh, source.rstrip("/") + "/", remote]
        process = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
        if process.returncode != 0:
            raise TransportError(process.stderr.decode("utf-8", "replace").strip())

    def push_tree(self, source: str, destination: str) -> None:
        self._rsync(source, destination, pull=False)

    def pull_tree(self, source: str, destination: str) -> None:
        self._rsync(source, destination, pull=True)

    def preflight(self) -> dict:
        process = self.run_py(
            "import json,os,platform,shutil,sys\n"
            "missing=[c for c in ('python3','rsync') if shutil.which(c) is None]\n"
            "print(json.dumps({'hostname':os.uname().nodename,'machine':platform.machine(),"
            "'missing':missing,'path':os.environ.get('PATH','')}))\n",
            [],
            timeout=45,
        )
        if process.returncode != 0:
            raise TransportError(
                "SSH authorization or host identity check failed: "
                + process.stderr.decode("utf-8", "replace").strip()
            )
        value = json.loads(process.stdout.decode("utf-8"))
        if value.get("missing"):
            raise TransportError(
                "executor lacks required tools: " + ", ".join(value["missing"])
            )
        return value


def cleanup(path: str) -> None:
    """Remove a capture directory this process created."""
    shutil.rmtree(path, ignore_errors=True)
