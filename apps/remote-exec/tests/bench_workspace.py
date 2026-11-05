#!/usr/bin/env python3
"""Reproducible warm-workspace timing on a generic fixture.

Not part of the unit suite: run it explicitly to measure what workspace reuse
costs and saves on the machine that executes the build.

    PYTHONPATH=apps/remote-exec python3 apps/remote-exec/tests/bench_workspace.py

The fixture has no language-specific cache logic. Its "build" is a generic
mtime-based step: it is skipped when the retained output is newer than every
source file, and that only happens because an unchanged sync preserves source
mtimes and leaves the retained output in place.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import uuid

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from remote_exec import attempt as attempt_module
from remote_exec import source, transport, workspace as workspace_module

BUILD = """
set -e
mkdir -p target
if [ -f target/out ] && [ -z "$(find src -newer target/out -print -quit)" ]; then
  echo HIT >> target/count
else
  sleep 0.4
  touch target/out
  echo MISS >> target/count
fi
"""


def git(repo, *args):
    env = dict(os.environ)
    env.update(
        {
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_NAME": "Bench",
            "GIT_AUTHOR_EMAIL": "bench@example.invalid",
            "GIT_COMMITTER_NAME": "Bench",
            "GIT_COMMITTER_EMAIL": "bench@example.invalid",
        }
    )
    subprocess.run(["git", "-C", repo, *args], env=env, check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def make_repo(root):
    repo = os.path.join(root, "repo")
    os.makedirs(os.path.join(repo, "src"))
    for index in range(80):
        with open(os.path.join(repo, "src", "file-%03d.txt" % index), "w", encoding="utf-8") as handle:
            handle.write("source %d\n" % index)
    with open(os.path.join(repo, ".gitignore"), "w", encoding="utf-8") as handle:
        handle.write("target/\n")
    git(repo, "init", "-q")
    git(repo, "config", "user.name", "Bench")
    git(repo, "config", "user.email", "bench@example.invalid")
    git(repo, "add", "-A")
    git(repo, "-c", "commit.gpgsign=false", "commit", "-qm", "base")
    return repo


def one_run(workspace, repo, run_id, local_transport):
    attempt = workspace_module.WorkspaceAttempt(local_transport, workspace, str(uuid.uuid4()))
    started = time.monotonic()
    attempt.prepare()
    capture_dir = attempt_module.capture_to(repo)
    try:
        attempt_module.add_runtime_files(capture_dir)
        with open(os.path.join(capture_dir, "input-files.json"), encoding="utf-8") as handle:
            captured = json.load(handle)
        local_transport.push_tree(capture_dir, attempt.staging)
        attempt.verify_input(captured["inputId"])
        workspace.sync(
            attempt.attempt_id,
            captured["inputId"],
            f"{attempt.staging}/input-files.json",
            f"{attempt.staging}/manifest.py",
        )
        attempt.publish(
            {
                "schemaVersion": 2,
                "attemptId": attempt.attempt_id,
                "inputId": captured["inputId"],
                "runId": run_id,
            }
        )
        result = attempt.dispatch(
            ["sh", "-c", BUILD], ".", 120, {"PATH": os.environ["PATH"]}, captured["inputId"]
        )
    finally:
        transport.cleanup(capture_dir)
    elapsed = time.monotonic() - started
    count_path = os.path.join(workspace.path, "work", "target", "count")
    with open(count_path, encoding="utf-8") as handle:
        decision = handle.read().strip().splitlines()[-1]
    return elapsed, decision, result["phase"]


def main():
    root = tempfile.mkdtemp(prefix="remote-exec-bench-")
    try:
        repo = make_repo(root)
        executor = os.path.join(root, "executor")
        os.makedirs(executor, 0o700)
        local_transport = transport.LocalTransport()
        workspace = workspace_module.Workspace(
            local_transport,
            executor,
            "local",
            None,
            "bench",
            "timing",
            source.repo_identity(repo),
        )
        cold, cold_decision, cold_phase = one_run(workspace, repo, "cold", local_transport)
        warm, warm_decision, warm_phase = one_run(workspace, repo, "warm", local_transport)
        with open(os.path.join(repo, "src", "file-000.txt"), "w", encoding="utf-8") as handle:
            handle.write("changed source\n")
        git(repo, "add", "-A")
        git(repo, "-c", "commit.gpgsign=false", "commit", "-qm", "change")
        changed, changed_decision, changed_phase = one_run(workspace, repo, "changed", local_transport)
        print(json.dumps({
            "fixture": {"sourceFiles": 80, "buildSleepSeconds": 0.4},
            "coldSeconds": round(cold, 3),
            "repeatSeconds": round(warm, 3),
            "oneSourceChangeSeconds": round(changed, 3),
            "buildDecisions": {
                "cold": cold_decision,
                "repeat": warm_decision,
                "oneSourceChange": changed_decision,
            },
            "phases": {
                "cold": cold_phase,
                "repeat": warm_phase,
                "oneSourceChange": changed_phase,
            },
        }, indent=2, sort_keys=True))
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    main()
