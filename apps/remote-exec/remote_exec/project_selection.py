"""Git's own view of new source, shared by fresh collection and snapshots.

The private bare Git directory lives outside the work tree: no repository
history, hooks or credentials participate. Callers apply the manifest path and
credential/agent-state boundary to the returned names.
"""

from __future__ import annotations

import os
import subprocess


class SelectionError(Exception):
    """The work tree could not be queried as a source selection."""


def git_selected(work: str, git_dir: str, home: str) -> list[str]:
    os.makedirs(home, exist_ok=True)
    gitconfig = os.path.join(home, "gitconfig")
    with open(gitconfig, "w", encoding="utf-8") as handle:
        handle.write("[core]\n\texcludesFile =\n")
    env = dict(os.environ)
    env.update(
        {
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": gitconfig,
            "GIT_TERMINAL_PROMPT": "0",
            "HOME": home,
            "LC_ALL": "C",
        }
    )
    if not os.path.isdir(git_dir):
        subprocess.run(["git", "init", "--bare", "--quiet", git_dir], check=True, env=env)
    process = subprocess.run(
        [
            "git", "--git-dir", git_dir, "--work-tree", work,
            "-c", "core.excludesFile=/dev/null",
            "ls-files", "-z", "--others", "--exclude-per-directory=.gitignore",
        ],
        cwd=work,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        check=False,
    )
    if process.returncode != 0:
        raise SelectionError(
            process.stderr.decode("utf-8", "replace").strip() or "git selection failed"
        )
    return [
        name
        for name in process.stdout.decode("utf-8", "surrogateescape").split("\0")
        if name
    ]
