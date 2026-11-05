"""Command line surface for remote-exec.

Exit codes are part of the contract:

    0  the command ran and exited 0
    1  the command ran and failed
    2  blocked before dispatch, or the input did not verify
    3  outcome unknown; reconcile (or cancel) the same attempt
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
INVENTORY_SCHEMA = 2


def load_inventory(value: str | None) -> dict:
    path = value or os.environ.get("REMOTE_EXEC_INVENTORY") or DEFAULT_INVENTORY
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except OSError as error:
        raise attempt_module.Blocked(f"cannot read the host inventory at {path}: {error}") from error
    if data.get("schemaVersion") != INVENTORY_SCHEMA or not isinstance(data.get("hosts"), dict):
        raise attempt_module.Blocked(f"unsupported inventory at {path}")
    return data


def resolve_target(value: str | None, name: str) -> tuple[dict, dict]:
    inventory = load_inventory(value)
    host = inventory["hosts"].get(name)
    if host is None:
        raise attempt_module.Blocked(f"target {name!r} is not a declared executor")
    executor = host.get("executor")
    if not executor:
        raise attempt_module.Blocked(
            f"target {name!r} has no declared executor account; enable the remote-exec feature there"
        )
    if not host.get("sshAddress"):
        raise attempt_module.Blocked(f"target {name!r} has no SSH-reachable address")
    for field in ("user", "root", "hostKey", "runtimePath"):
        if not executor.get(field):
            raise attempt_module.Blocked(f"target {name!r} declares no executor {field}")
    return host, executor


def make_transport(args, host: dict | None, executor: dict | None) -> transport.Transport:
    if args.transport == "local":
        return transport.LocalTransport()
    if not args.identity:
        raise attempt_module.Blocked("--identity is required: no implicit SSH credential discovery")
    identity = os.path.abspath(os.path.expanduser(args.identity))
    if not os.path.isfile(identity):
        raise attempt_module.Blocked(f"identity file {identity} does not exist")
    return transport.SshTransport(
        user=executor["user"],
        address=host["sshAddress"],
        host_key=executor["hostKey"],
        identity=identity,
    )


def check_executor(
    transport_: transport.Transport,
    target: str | None,
    host: dict | None,
    executor: dict | None,
    root: str,
) -> dict:
    observed = transport_.preflight(root)
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
        if observed.get("user") != executor["user"]:
            raise attempt_module.Blocked(
                f"executor account mismatch: inventory says {executor['user']!r}, login is {observed.get('user')!r}"
            )
        if observed.get("uid") == 0:
            raise attempt_module.Blocked("refusing to run as uid 0; the executor account must be non-root")
        if observed.get("root") != executor["root"]:
            raise attempt_module.Blocked(
                f"remote root mismatch: inventory says {executor['root']!r}, resolved {observed.get('root')!r}"
            )
        if observed.get("rootOwner") not in (None, observed.get("uid")):
            raise attempt_module.Blocked("the declared remote root is not owned by the executor account")
        if observed.get("rootWritable") is False:
            raise attempt_module.Blocked("the declared remote root is not writable by the executor account")
        if observed.get("userManager") is False:
            raise attempt_module.Blocked(
                "the executor account has no reachable user systemd manager (linger declared?)"
            )
        if observed.get("missing"):
            raise attempt_module.Blocked(
                "executor lacks required tools: " + ", ".join(observed["missing"])
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
    add_attempt_arguments(status)
    status.add_argument("--json", action="store_true")

    cancel = sub.add_parser("cancel", help="stop the attempt's unit and report its state")
    add_attempt_arguments(cancel)

    collect = sub.add_parser("collect", help="fetch the selected output of a terminal attempt")
    add_attempt_arguments(collect)
    collect.add_argument("--out", required=True)
    collect.add_argument("--logs", action="store_true")
    collect.add_argument("--artifacts", action="store_true")
    collect.add_argument("--delta", action="store_true")

    run = sub.add_parser("run", help="capture, transfer, verify, execute and observe one attempt")
    add_attempt_arguments(run)
    run.add_argument("--repo", required=True)
    run.add_argument("--cwd", default=".")
    run.add_argument("--timeout", type=int, default=1800)
    run.add_argument("--env", action="append", default=[])
    run.add_argument("--extra-path", action="append", default=[])
    run.add_argument("argv", nargs=argparse.REMAINDER, metavar="command")

    sub.add_parser("inventory", help="print the resolved executor table")
    return parser.parse_args(argv)


def add_attempt_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--transport", choices=("ssh", "local"), default="ssh")
    parser.add_argument("--target", help="inventory host name")
    parser.add_argument("--identity", help="explicit SSH private key for the executor account")
    parser.add_argument("--remote-root", help="must equal the executor's declared root (ssh), or the test root (local)")
    parser.add_argument("--repo-id", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--attempt-id")


def attempt_from(args) -> tuple[attempt_module.Attempt, dict | None, dict | None]:
    host = executor = None
    if args.transport == "ssh":
        if not args.target:
            raise attempt_module.Blocked("--target is required for the ssh transport")
        host, executor = resolve_target(args.inventory, args.target)
        if args.remote_root and args.remote_root != executor["root"]:
            raise attempt_module.Blocked(
                f"--remote-root must equal the declared executor root {executor['root']!r}"
            )
        root = executor["root"]
    else:
        if args.target is not None:
            raise attempt_module.Blocked("--target is not used by the local transport")
        if not args.remote_root:
            raise attempt_module.Blocked("--remote-root is required")
        root = args.remote_root
    # The path is closed over the client object; make_transport needs it.
    args._root = root
    transport_ = make_transport(args, host, executor)
    attempt_id = args.attempt_id or attempt_module.new_attempt_id()
    attempt = attempt_module.Attempt(transport_, root, args.repo_id, args.run_id, attempt_id)
    return attempt, host, executor


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
    attempt, _, _ = attempt_from(args)
    state = attempt.status()
    print(json.dumps(state, indent=2, sort_keys=True) if args.json else json.dumps(state))
    return 0


def command_cancel(args) -> int:
    if not args.attempt_id:
        raise attempt_module.Blocked("--attempt-id is required to cancel an existing attempt")
    attempt, _, _ = attempt_from(args)
    state = attempt.cancel()
    print(json.dumps(state, indent=2, sort_keys=True))
    if state.get("terminal"):
        return 0 if state.get("phase") == "cancelled" else 1
    return 3


def command_collect(args) -> int:
    if not args.attempt_id:
        raise attempt_module.Blocked("--attempt-id is required to collect an existing attempt")
    attempt, _, _ = attempt_from(args)
    if os.path.exists(args.out) and os.listdir(args.out):
        raise attempt_module.Blocked(f"collect target {args.out} is not empty")
    result = attempt.collect(
        args.out, with_logs=args.logs, with_artifacts=args.artifacts, with_delta=args.delta
    )
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result.get("phase") == "succeeded" else 1


def command_run(args) -> int:
    argv = list(args.argv)
    if argv and argv[0] == "--":
        argv = argv[1:]
    if not argv:
        raise attempt_module.Blocked("no command given after --")

    attempt, host, executor = attempt_from(args)
    observed = check_executor(attempt.transport, args.target, host, executor, args._root)
    if args.transport == "local" and observed.get("uid") == 0:
        raise attempt_module.Blocked("refusing to run the local fixture transport as root")

    capture_dir = attempt_module.capture_to(args.repo, tuple(args.extra_path))
    try:
        attempt_module.add_runtime_files(capture_dir)
        with open(os.path.join(capture_dir, "input-files.json"), "r", encoding="utf-8") as handle:
            captured = json.load(handle)

        attempt.prepare()
        attempt.transport.push_tree(capture_dir, attempt.staging)
        attempt.verify_input(captured["inputId"])

        env = env_pairs(args.env)
        if "PATH" not in env:
            env["PATH"] = (executor or {}).get("runtimePath") or observed.get("path") or ""

        input_meta = {
            "schemaVersion": 2,
            "repoId": attempt.repo_id,
            "runId": attempt.run_id,
            "attemptId": attempt.attempt_id,
            "target": args.target or "local",
            "executor": {
                "host": args.target or "local",
                "address": (host or {}).get("sshAddress"),
                "user": (executor or {}).get("user") or observed.get("user"),
                "uid": observed.get("uid"),
                "root": args._root,
                "architecture": observed.get("machine"),
            },
            "baseRevision": captured["baseRevision"],
            "inputId": captured["inputId"],
            "command": argv,
            "cwd": args.cwd,
            "environment": env,
        }
        attempt.publish(input_meta)

        try:
            result = attempt.dispatch(
                argv=argv, cwd=args.cwd, timeout_secs=args.timeout, env=env, input_id=captured["inputId"]
            )
        except attempt_module.UnknownOutcome as unknown:
            print(
                json.dumps(
                    {
                        "attemptId": unknown.attempt_id,
                        "inputId": captured["inputId"],
                        "phase": unknown.state.get("phase", "unknown"),
                        "reason": unknown.state.get("reason")
                        or "no terminal observation; reconcile the same attempt",
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


def command_inventory(args) -> int:
    print(json.dumps(load_inventory(args.inventory), indent=2, sort_keys=True))
    return 0


COMMANDS = {
    "capture": command_capture,
    "verify": command_verify,
    "status": command_status,
    "cancel": command_cancel,
    "collect": command_collect,
    "run": command_run,
    "inventory": command_inventory,
}


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        return COMMANDS[args.command](args)
    except attempt_module.Blocked as error:
        print(f"remote-exec: {error}", file=sys.stderr)
        return 2
    except (source.SourceError, manifest.ManifestError, transport.TransportError) as error:
        print(f"remote-exec: {error}", file=sys.stderr)
        return 2
