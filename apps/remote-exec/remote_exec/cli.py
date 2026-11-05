"""Command line surface for remote-exec.

Exit codes are part of the contract:

    0  the command ran and exited 0
    1  the command ran and failed
    2  blocked before dispatch, or the input did not verify
    3  outcome unknown; reconcile the same attempt
    4  a delta conflicts with the current target
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys

from . import attempt as attempt_module
from . import manifest, source, transport

DEFAULT_INVENTORY = "/etc/openclaw/remote-exec-inventory.json"


def inventory_path(value: str | None) -> str:
    return value or os.environ.get("REMOTE_EXEC_INVENTORY") or DEFAULT_INVENTORY


def load_inventory(value: str | None) -> dict:
    path = inventory_path(value)
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except OSError as error:
        raise attempt_module.Blocked(f"cannot read the host inventory at {path}: {error}") from error
    if data.get("schemaVersion") != 1 or not isinstance(data.get("hosts"), dict):
        raise attempt_module.Blocked(f"unsupported inventory at {path}")
    return data


def resolve_target(value: str | None, name: str) -> tuple[dict, dict]:
    inventory = load_inventory(value)
    host = inventory["hosts"].get(name)
    if host is None:
        raise attempt_module.Blocked(f"target {name!r} is not a declared host")
    if host.get("hostType") not in ("server", "workstation"):
        raise attempt_module.Blocked(f"target {name!r} is a {host.get('hostType')}, not an executor")
    if not host.get("sshAddress"):
        raise attempt_module.Blocked(f"target {name!r} has no SSH-reachable address")
    return host, inventory


def make_transport(args) -> transport.Transport:
    if args.transport == "local":
        return transport.LocalTransport(root=args.remote_root)
    if not args.ssh_user:
        raise attempt_module.Blocked("--ssh-user is required for the ssh transport")
    host, _ = resolve_target(args.inventory, args.target)
    return transport.SshTransport(user=args.ssh_user, host=host["sshAddress"], identity=args.identity)


def check_executor(transport_: transport.Transport, target: str | None, host: dict | None) -> dict:
    observed = transport_.preflight()
    if target is not None:
        if observed.get("hostname") != target:
            raise attempt_module.Blocked(
                f"executor identity mismatch: asked for {target}, connected to {observed.get('hostname')!r}"
            )
        expected = (host or {}).get("architecture")
        if expected and observed.get("machine") != expected:
            raise attempt_module.Blocked(
                f"executor architecture mismatch: expected {expected}, measured {observed.get('machine')}"
            )
    return observed


def env_pairs(values: list[str]) -> dict:
    result = {}
    for item in values:
        key, separator, value = item.partition("=")
        if not separator or not key:
            raise attempt_module.Blocked(f"--env expects KEY=VALUE, got {item!r}")
        result[key] = value
    return result


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="remote-exec", description=__doc__)
    parser.add_argument("--inventory", help="host inventory JSON (default: $REMOTE_EXEC_INVENTORY)")
    sub = parser.add_subparsers(dest="command", required=True)

    capture = sub.add_parser("capture", help="export a Git working tree and write its manifest")
    capture.add_argument("--repo", required=True)
    capture.add_argument("--out", required=True)
    capture.add_argument("--extra-path", action="append", default=[])

    verify = sub.add_parser("verify", help="recompute a manifest and compare it")
    verify.add_argument("--root", required=True)
    verify.add_argument("--manifest", required=True)
    verify.add_argument("--expect-input-id")

    status = sub.add_parser("status", help="observe an attempt without dispatching anything")
    add_attempt_arguments(status, transport_required=True)
    status.add_argument("--json", action="store_true")

    collect = sub.add_parser("collect", help="fetch a terminal result and its artifacts")
    add_attempt_arguments(collect, transport_required=True)
    collect.add_argument("--out", required=True)
    collect.add_argument("--logs", action="store_true")
    collect.add_argument("--delta", action="store_true")

    run = sub.add_parser("run", help="capture, transfer, execute and collect one attempt")
    add_attempt_arguments(run, transport_required=True)
    run.add_argument("--repo", required=True)
    run.add_argument("--node-id", required=True, help="pinned native node identity for this attempt")
    run.add_argument("--cwd", default=".")
    run.add_argument("--timeout", type=int, default=1800)
    run.add_argument("--env", action="append", default=[])
    run.add_argument("--extra-path", action="append", default=[])
    run.add_argument("argv", nargs=argparse.REMAINDER, metavar="command")

    apply_delta = sub.add_parser("apply-delta", help="apply a collected delta to the exact base input")
    apply_delta.add_argument("--delta", required=True)
    apply_delta.add_argument("--source", required=True)
    apply_delta.add_argument("--target", required=True)

    inventory = sub.add_parser("inventory", help="print the resolved executor table")
    return parser.parse_args(argv)


def add_attempt_arguments(parser: argparse.ArgumentParser, transport_required: bool) -> None:
    parser.add_argument("--transport", choices=("ssh", "local"), default="ssh")
    parser.add_argument("--target", help="inventory host name")
    parser.add_argument("--ssh-user")
    parser.add_argument("--identity")
    parser.add_argument("--remote-root", required=True)
    parser.add_argument("--repo-id", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--attempt-id")


def attempt_from(args) -> attempt_module.Attempt:
    if not args.target and args.transport == "ssh":
        raise attempt_module.Blocked("--target is required for the ssh transport")
    if args.transport == "local" and args.target is not None:
        raise attempt_module.Blocked("--target is not used by the local transport")
    transport_ = make_transport(args)
    attempt_id = args.attempt_id or attempt_module.new_attempt_id()
    return attempt_module.Attempt(
        transport_, args.remote_root, args.repo_id, args.run_id, attempt_id
    )


def command_capture(args) -> int:
    value = source.capture(args.repo, args.out, tuple(args.extra_path))
    print(json.dumps({"inputId": value["inputId"], "baseRevision": value["baseRevision"],
                      "files": len(value["files"])}))
    return 0


def command_verify(args) -> int:
    value = manifest.verify(args.root, args.manifest, args.expect_input_id)
    print(json.dumps({"inputId": value}))
    return 0


def command_status(args) -> int:
    if not args.attempt_id:
        raise attempt_module.Blocked("--attempt-id is required to observe an existing attempt")
    attempt = attempt_from(args)
    state = attempt.status()
    print(json.dumps(state, indent=2, sort_keys=True) if args.json else json.dumps(state))
    return 0


def command_collect(args) -> int:
    if not args.attempt_id:
        raise attempt_module.Blocked("--attempt-id is required to collect an existing attempt")
    attempt = attempt_from(args)
    if os.path.exists(args.out) and os.listdir(args.out):
        raise attempt_module.Blocked(f"collect target {args.out} is not empty")
    result = attempt.collect(args.out, with_logs=args.logs, with_delta=args.delta)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result.get("phase") == "succeeded" else 1


def command_run(args) -> int:
    if not args.argv:
        raise attempt_module.Blocked("no command given after --")
    argv = list(args.argv)
    if argv and argv[0] == "--":
        argv = argv[1:]
    if not argv:
        raise attempt_module.Blocked("no command given after --")

    host, _ = resolve_target(args.inventory, args.target) if args.transport == "ssh" else ({}, {})
    attempt = attempt_from(args)
    observed = check_executor(attempt.transport, args.target, host)

    capture_dir = attempt_module.capture_to(args.repo, tuple(args.extra_path))
    try:
        attempt_module.add_verifier(capture_dir)
        with open(os.path.join(capture_dir, "input-files.json"), "r", encoding="utf-8") as handle:
            captured = json.load(handle)

        attempt.prepare()
        attempt.transport.push_tree(capture_dir, attempt.staging)
        try:
            attempt.verify(captured["inputId"])
        except attempt_module.Blocked as error:
            raise attempt_module.Blocked(f"input verification failed, attempt not published: {error}") from error

        env = env_pairs(args.env)
        if "PATH" not in env:
            env["PATH"] = observed.get("path") or ""

        attempt.write(
            f"{attempt.staging}/input.json",
            json.dumps(
                {
                    "schemaVersion": 1,
                    "repoId": attempt.repo_id,
                    "runId": attempt.run_id,
                    "attemptId": attempt.attempt_id,
                    "nodeId": args.node_id,
                    "target": args.target or "local",
                    "baseRevision": captured["baseRevision"],
                    "inputId": captured["inputId"],
                    "command": argv,
                    "cwd": args.cwd,
                    "environment": env,
                    "architecture": observed.get("machine"),
                },
                indent=2,
                sort_keys=True,
            )
            + "\n",
        )
        attempt.publish()

        try:
            result = attempt.run(
                argv=argv,
                cwd=args.cwd,
                timeout_secs=args.timeout,
                env=env,
                node_id=args.node_id,
                input_id=captured["inputId"],
            )
        except subprocess.TimeoutExpired:
            # The transport gave up before the executor did. The attempt is
            # published and may still be running; this is not a failure.
            print(
                json.dumps(
                    {
                        "attemptId": attempt.attempt_id,
                        "inputId": captured["inputId"],
                        "phase": "unknown",
                        "reason": "transport timed out; reconcile the same attempt with `status`",
                    },
                    indent=2,
                    sort_keys=True,
                )
            )
            return 3
        print(json.dumps(result, indent=2, sort_keys=True))
        phase = result.get("phase")
        if phase == "succeeded":
            return 0
        if phase in ("failed", "cancelled"):
            return 1
        return 3
    finally:
        transport.cleanup(capture_dir)


def command_apply_delta(args) -> int:
    applied = attempt_module.apply_delta(args.delta, args.source, args.target)
    print(json.dumps(applied, sort_keys=True))
    return 0


def command_inventory(args) -> int:
    data = load_inventory(args.inventory)
    print(json.dumps(data, indent=2, sort_keys=True))
    return 0


COMMANDS = {
    "capture": command_capture,
    "verify": command_verify,
    "status": command_status,
    "collect": command_collect,
    "run": command_run,
    "apply-delta": command_apply_delta,
    "inventory": command_inventory,
}


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        return COMMANDS[args.command](args)
    except attempt_module.Blocked as error:
        print(f"remote-exec: {error}", file=sys.stderr)
        return 4 if args.command == "apply-delta" else 2
    except (source.SourceError, manifest.ManifestError, transport.TransportError) as error:
        print(f"remote-exec: {error}", file=sys.stderr)
        return 2
