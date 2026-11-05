# Remote execution

A selected node can build and test one identifiable snapshot of a Gateway-held working tree. The
parent conversation, the edits and the integration stay on the Gateway; the node is an executor for a
bounded attempt, not a second session host and not a shared writable checkout.

## What an attempt is

The normal operation is one command, `remote-exec run`. It performs four steps internally:

1. **Select and capture.** `remote-exec capture` asks Git which paths are source. Tracked paths are
   exported from the working tree even when dirty, staged or matched by an ignore rule; a tracked path
   missing from the working tree is a deletion. Untracked paths are admitted by the project's own
   `.gitignore` files, nested rules and negations included. `~/.config/git/ignore` and
   `.git/info/exclude` are not consulted, so a personal setting cannot change the input. `.git` is
   never exported. The result is a real copy under `work/` and a manifest: relative path, type,
   `100644`/`100755`/`120000`, size and SHA-256 (or symlink target). `inputId` is a SHA-256 over the
   canonical manifest.
2. **Transfer.** rsync over an authenticated SSH connection to a fresh attempt directory. No owner or
   group ids are preserved; files arrive owned by the executor account.
3. **Verify, then publish.** A verifier running on the executor recomputes the manifest from
   `work/` and compares it with `input-files.json` and `inputId`. A mismatch leaves the staging
   directory unpublished and the attempt cannot run. Only a verified tree is renamed to its attempt
   name, so an incomplete upload never becomes runnable input.
4. **Execute and collect.** The command runs in its own process group under an attempt-local `HOME`,
   `TMPDIR` and `REMOTE_EXEC_ARTIFACTS`. The runner writes `state.json` while the command lives and
   one atomic `result.json` when it ends. `remote-exec collect` fetches the result, artifacts and,
   optionally, logs and a source delta.

The executor layout is:

    <remote-root>/<repo-id>/<run-id>/<attempt-id>/
      input.json  input-files.json  manifest.py  verify.py
      work/  home/  tmp/  logs/  artifacts/  state.json  result.json

An attempt id is never reused. A build's generated files stay in `work/` and are outputs, not edits
to the canonical source. `work/` is a real copy, never a hardlink into a cache, and no directory is
shared writable between attempts.

## Commands

```bash
remote-exec run \
  --target hom-wrk-01 --ssh-user <account> --remote-root /var/lib/remote-exec \
  --repo-id nixfiles --run-id <native-run-id> --node-id <native-node-id> \
  --repo /path/to/worktree --timeout 1800 \
  -- nix flake check

remote-exec status  --target hom-wrk-01 --ssh-user <account> --remote-root /var/lib/remote-exec \
  --repo-id nixfiles --run-id <native-run-id> --attempt-id <id>
remote-exec collect --target hom-wrk-01 --ssh-user <account> --remote-root /var/lib/remote-exec \
  --repo-id nixfiles --run-id <native-run-id> --attempt-id <id> --out ./result --logs --delta
remote-exec apply-delta --delta ./result/delta.json --source ./result/source --target /path/to/worktree

# inspection and recovery only:
remote-exec capture --repo /path/to/worktree --out /tmp/capture
remote-exec verify  --root /tmp/capture/work --manifest /tmp/capture/input-files.json
```

`capture` and `verify` are the pieces `run` composes; they are useful for a diagnosed
capture and for reproducing a manifest, not as a manual substitute for the operation.
`status` and `collect` are required after a disconnect: an attempt id, not a repeated
command, is how an uncertain outcome is reconciled.

`exec` with `host=<node>` stays raw node execution. It does not export, transfer or verify
repository source, so it is not a remote build path for a Gateway worktree; a command that
needs the repository must go through `remote-exec run`.

`--transport local` runs the same contract against a local directory. It exists for the fixture
suite; production attempts require a named inventory host and SSH account. The inventory is generated
by `my.features.services.openclaw.gateway` at
`/etc/openclaw/remote-exec-inventory.json` from `my.topology.hosts` and the naming projection, so the
host table has one source. A target must be declared, have an SSH address, and be a `server` or
`workstation`; the executor's `hostname` and architecture must match it before any bytes move.

Exit codes: `0` command succeeded, `1` command ran and failed, `2` blocked or input did not verify,
`3` outcome unknown (reconcile the same attempt), `4` delta conflict.

## Failure semantics

A disconnect, Stop or timeout is not success and not confirmed cancellation. `result.json` is
written by the executor, so after a lost connection `status` reports `running`, a terminal phase, or
`unknown` when the recorded process is gone without a result or the node rebooted. Reconcile that
attempt id; do not start a replacement command because a response was lost. A timeout is reported as
`cancelled` only after the owned process group has exited; otherwise it is `unknown`.

There is no exactly-once guarantee: an attempt id is a directory identity, not a distributed
transaction. Commands that mutate external state (deploy, release, publish) belong to the operator
and their own authorization, not to an automatically retried build attempt.

## Inputs this tool refuses

* submodules (a gitlink) and Git LFS attributes — a pointer file or a borrowed object store is not
  the content a build needs;
* absolute or escaping symlinks, and anything but regular files and symlinks;
* a working tree whose `HEAD` or Git index changes during capture;
* a capture whose target is not empty, and an attempt directory that already exists.

Generated inputs that a project's build does not reproduce can be named with `--extra-path`; they
are explicit, not a second ignore policy.

## Prerequisites on an executor

The executor needs Python 3, rsync, and SSH authorization for a non-root account that owns the
remote root. These are operator-owned: the repository declares the inventory and packages the tool,
but it deliberately creates no key, account, directory or service. Until that authorization and a
writable root exist, a production attempt is blocked at preflight — a named pre-activation gate, not
a reason to send the job to another host.

Worktree isolation is not an OS security boundary. Untrusted repository code must run under an
execution account and sandbox appropriate to that risk.
