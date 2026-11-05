# Remote execution

A selected node can build and test one identifiable snapshot of a Gateway-held working tree. The
parent conversation, edits and integration stay on the Gateway; the node is an executor for a
bounded attempt, not a session host and not a shared writable checkout.

## One operation

`remote-exec run` captures the current worktree, transfers it, verifies the executor and input, then
supervises the command and reports its terminal state. There is no separate prepare/sync/verify
sequence to coordinate, and no assumption that a node already holds the source. A later invocation
captures the later tree; a running attempt keeps the input it started with.

The attempt is dispatched at most once. Its directory is created with `mkdir` (atomic on the
executor), `input.json` is published last, and `dispatch.json` is created with `O_CREAT|O_EXCL`. A
duplicate or concurrent request for the same attempt id observes the existing state and never stages
or runs it again. A preparation interrupted before `input.json` reports `interrupted` and is not
runnable.

## Executor identity

Identity is the inventory plus a pinned SSH host key plus a declared non-root account:

- `/etc/openclaw/remote-exec-inventory.json` is generated from `my.topology.hosts` and only from
  hosts that enabled `my.features.services.remote-exec`. Each eligible entry carries the account,
  root, runtime PATH and SSH host key.
- The CLI connects to the declared address, checks the host key against that entry, and verifies
  on the executor: the login account equals the declared non-root account, uid is not 0, the root
  realpath equals the declared root, and the root is owned by and writable to that account.
- `--identity` is required; OpenSSH default credential discovery is disabled with
  `IdentitiesOnly=yes`. The gateway's dedicated executor key is the SOPS secret
  `services/remote_exec/ssh_private_key`, readable only by `openclaw`.
- A native pairing id or a device selected in a client UI is not this identity and is not accepted
  as one. Session placement and SSH execution are separate decisions.

The executor declaration is opt-in. `hom-wrk-01` is the current canary; no other host enables the
module.

## What an attempt contains

    <root>/<repo-id>/<run-id>/<attempt-id>/
      input.json  input-files.json  output-files.json
      manifest.py boundary.py verify.py  runner.py  runner-config.json
      work/  home/ tmp/ logs/ artifacts/
      dispatch.json  state.json  result.json

`work/` holds real copies, never hardlinks into a cache. Attempt-local `HOME`, `TMPDIR` and
`REMOTE_EXEC_ARTIFACTS` keep caches and outputs out of the source tree. An attempt directory is never
reused.

## Source selection

Git decides source. Tracked paths are exported from the working tree even when dirty, staged or
matched by an ignore rule; a tracked path missing from the worktree is a deletion. Untracked paths
follow the project's own `.gitignore` files, nested rules and negations. The query uses
`--exclude-per-directory=.gitignore` with a neutral `core.excludesFile`, so `~/.config/git/ignore`
and `.git/info/exclude` cannot change the input.

Independently of ignore rules, `.env` files (except `.example`/`.sample`/`.template`/`.dist`),
SSH/cloud/agent state directories, private-key suffixes and common credential files are refused
with a named error. This is a name boundary, not a secret scanner; the executor account remains the
trust boundary.

The caller is the sole writer for the capture window. The tool does not claim an atomic snapshot:
it compares the selected path set, HEAD, the Git index and every captured file's digest before it
publishes a manifest, and fails if any of them moved. `.git` is never exported; submodules and Git
LFS attributes fail closed.

## Supervision and cancellation

On SSH the attempt is a transient user unit (systemd-run --user) in the executor account's manager,
which the module declares with lingering enabled. The runner owns the command's process group and
writes one atomic `result.json`. An SSH disconnect does not kill the attempt; a reconnect reconciles
the same attempt id with `status`.

`cancel` stops the unit and reports `cancelled` only when the unit and its process group are gone.
`RuntimeMaxSec` and the runner's own timeout both end in a terminal observation; a group that
survives is `unknown`. There is no exactly-once guarantee for external side effects, and a lost
response is never replayed. A command that mutates shared external state belongs to an operator
workflow, not an automatically retried build.

## Collection

Collection requires a terminal result tied to the recorded input id. It selects the baseline input
paths plus new project-nonignored source, using a private, empty Git metadata directory outside
`work/`; no repository history or credential-bearing config participates. Ignored build trees such
as `target/` or `node_modules/` and dependency caches are never downloaded.

The selected files are verified against `output-files.json`; requested logs are verified against the
result's hashes. Artifacts are fetched only with `--artifacts`. `--delta` writes `delta.json` against
the recorded base input as a verified export for the integrator's ordinary Git workflow — the tool
never applies it to the live parent.

## Commands

```bash
remote-exec run \
  --target hom-wrk-01 --identity /run/secrets/services/remote_exec/ssh_private_key \
  --repo-id nixfiles --run-id <native-run-id> \
  --repo /path/to/worktree --timeout 1800 \
  -- nix flake check

remote-exec status  --target hom-wrk-01 --identity <key> --repo-id nixfiles \
  --run-id <id> --attempt-id <id>
remote-exec cancel  --target hom-wrk-01 --identity <key> --repo-id nixfiles \
  --run-id <id> --attempt-id <id>
remote-exec collect --target hom-wrk-01 --identity <key> --repo-id nixfiles \
  --run-id <id> --attempt-id <id> --out ./result --logs --delta
```

`capture` and `verify` are the pieces `run` composes; `status` and `collect` are required for
recovery. `--transport local` runs the same runner against a local directory for the fixture suite
only; its timeout says nothing about SSH transport or systemd supervision.

Exit codes: `0` command succeeded, `1` command ran and failed, `2` blocked or input did not verify,
`3` outcome unknown (reconcile or cancel the same attempt).

## Refusals

* submodules (a gitlink) and Git LFS attributes;
* absolute or escaping symlinks, and anything but regular files and symlinks;
* a worktree whose selection, `HEAD`, Git index or captured bytes change during capture;
* a capture target that is not empty, and an attempt id that already exists;
* an executor whose host key, account, uid, root or toolchain does not match its declaration;
* credential and agent-state paths, including explicit `--extra-path` inputs.

Generated inputs that a project's build does not reproduce can be named with `--extra-path`; they
are explicit, not a second ignore policy.

## Limits

Worktree isolation is not an OS security boundary. Untrusted repository code needs an execution
account and sandbox appropriate to that risk. A name-based credential boundary does not prove that
no semantic secret exists under an ordinary filename. The tool does not enforce that the caller is
the only writer; it detects changes during the capture window. A duplicate id prevents a second
dispatch of the same attempt, not two attempts with different ids performing the same external
effect.

## Declared prerequisites

The gateway installs the dedicated private key from SOPS and the generated inventory. The executor
module declares the non-root account, owned root, authorized public key, lingering user manager and
runtime tools. Enabling the module on a host and delivering the SOPS key is the complete
configuration; activation remains operator-owned. A host that has not enabled the module is not
eligible, even if it is paired or selected elsewhere.
