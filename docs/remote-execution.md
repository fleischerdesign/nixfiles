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

After a terminal result, `run` also fetches the attempt logs into
`$XDG_STATE_HOME/remote-exec/<repo>/<run>/<attempt>/`, verifies them against the result hashes, and
includes bounded stdout/stderr previews in its JSON. A failed diagnostic transfer appears as
`diagnostics.error` while the command's phase and remote exit code remain authoritative; it is a
diagnostic failure, not an unknown execution, and is never replayed.

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
- The inventory declares that path as `defaultIdentity`, so a normal gateway call needs no
  repeated key argument; `--identity` overrides it explicitly and implicit discovery stays
  disabled either way.
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

### Reusable task workspaces

A fresh attempt is the default and stays the isolation boundary for verification. Iterative work can
opt into a persistent task workspace with `--workspace-id`:

    <root>/workspaces/<key>/
      workspace.json           identity and binding metadata
      state/lease.json         exclusive ownership and phase
      state/managed.json       expected state of managed source paths
      state/synced.json        last verified input
      state/update-incomplete.json   present while a sync may be partial
      state/lock               flock serialising workspace transitions
      work/                    source plus retained tool output
      home/                    stable HOME for tool-native state
      staging/<attempt-id>/    incoming capture, never inside work/
      attempts/<attempt-id>/   receipts, logs, artifacts and source snapshot

`<key>` is hashed from the executor root/target/account, the repository identity (the canonical Git
common directory, never `.git` contents), the repo id and the workspace label. Two repositories
cannot share a workspace by reusing a label, and changing the label starts a different workspace.

Sequential attempts in one workspace are mutually exclusive: a lease covers sync, execution and
cancellation, and a second attempt is refused while it is not terminal. Parallel tasks use different
workspace ids. A lease that cannot be proven terminal is never taken over; reconcile with
`workspace-status`, `cancel`, or an explicit `workspace-reset`.

Reconciliation starts from the previous managed manifest. Unchanged files are not written, so their
mtimes survive and mtime-based incremental tools see a hit. Changed files get a current mtime.
Deleted and renamed source is removed; ignored output directories, generated results and other
unmanaged files stay. Modes, symlinks and file/directory type changes are applied. A symlinked or
non-directory ancestor, an unexpected remote edit of a managed source, or a new source path that
collides with retained output fails closed instead of deleting it. `rsync --delete` is never used
across retained output.

Sync writes an incomplete marker before mutating the work tree and publishes the verified manifest
only after success. A crash leaves the workspace marked and the next attempt refuses until the
partial sync is resolved. `--clean` is the explicit fresh mode inside a workspace: it discards
`work/` and `home/` and clears the managed manifest before the new attempt. A warm workspace is not a
hermetic build; retained output is valid only to the build tool that produced it.

Each workspace attempt freezes its selected source into `attempts/<id>/snapshot/` and writes
`output-files.json` at terminal time. `collect`, `--delta`, status, logs and artifacts for that
attempt therefore remain attempt-immutable even after later attempts mutate `work/`. If the snapshot
could not be produced, source collection is refused explicitly rather than reading later workspace
state.

`workspace-status` reports the workspace, lease, managed input, attempts and disk use, and reconciles
a lease whose attempt already has a terminal result. `workspace-reset` discards `work/` (and `home/`
with `--clean-home`) only when no dispatch, unit or live process can still be running; `--force` is
required for an unknown outcome after those checks. `workspace-prune` is a dry run by default: it
deletes only terminal attempts older than `--max-age-days` beyond `--keep`, skips a workspace with a
non-terminal lease, and `--apply` performs the deletion. `--remove-workspaces` additionally deletes
eligible, unused workspaces of this repository; no automated prune is scheduled.

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

# Iterative work reuses one task workspace; verification uses a fresh attempt
# or an explicit clean reset.
remote-exec run --target hom-wrk-01 --identity <key> --repo-id nixfiles \
  --workspace-id nixfiles-iter --repo /path/to/worktree -- nix build .#checks
remote-exec workspace-status --target hom-wrk-01 --identity <key> \
  --repo-id nixfiles --workspace-id nixfiles-iter --repo /path/to/worktree
remote-exec workspace-reset  --target hom-wrk-01 --identity <key> \
  --repo-id nixfiles --workspace-id nixfiles-iter --repo /path/to/worktree
remote-exec workspace-prune  --target hom-wrk-01 --identity <key> \
  --repo-id nixfiles --repo /path/to/worktree --keep 10 --max-age-days 14
```

`capture` and `verify` are the pieces `run` composes; `status` and `collect` are required for
recovery. `--transport local` runs the same runner against a local directory for the fixture suite
only; its timeout says nothing about SSH transport or systemd supervision.

## Source handoff for a native child

Implicit inheritance of a parent's dirty, untracked, deleted or executable state is not a supported
contract. The explicit handoff is `remote-exec checkpoint`:

```bash
remote-exec checkpoint --repo /path/to/worktree
remote-exec verify-source --repo . --expect-input-id <receipt.inputId>
```

`checkpoint` captures the same filtered, credential-scanned export as `run`, publishes it as a
standard-Git commit under the private namespace `refs/remote-exec/checkpoints/`, and prints:

```json
{
  "sourceRoot": "/path/to/worktree",
  "parentRevision": "<original HEAD>",
  "inputId": "<content-only id>",
  "checkpoint": {"id": "...", "commit": "...", "tree": "...", "ref": "refs/remote-exec/checkpoints/..."}
}
```

The commit is built with `hash-object --no-filters`, `mktree -z` and `commit-tree`, so clean,
smudge, eol and attribute conversion and hooks do not run. The caller's HEAD, index, branches and
working bytes are untouched; the original commit is kept as the checkpoint's parent for provenance.
Commit metadata is deterministic: author and committer dates inherit the captured parent's
committer timestamp, or the Unix epoch for an unborn repository. Wall-clock time is not part of the
checkpoint, so identical captured provenance, parent and identity produce the same commit object.
The ref is the retention record. A default checkpoint call generates an independent UUID pin, so two
consumers of the same input never share a releasable ref. An explicit `--id` is a logical consumer
or retry id: replay returns the existing commit only when its tree, parent and input id all match
the current capture; a different input, parent or tree under the same id is refused. Keep a pin
until the consumer is bound and settled.
`checkpoint-release --expect-commit` deletes only an owned ref, with CAS, and is idempotent when the
ref is already absent.

Pass `worktree=true`, `cwd=<sourceRoot>` and `worktreeBaseRef=<checkpoint.commit>` to
`sessions_spawn`, and put `expectedInputId` in the child task. The child runs `verify-source` before
any edit or build; a mismatch stops it. Integrate child changes after the checkpoint through normal
Git; the tool does not merge or apply a synthetic checkpoint.

Exit codes: `0` command succeeded, `1` command ran and failed, `2` blocked or input did not verify,
`3` outcome unknown (reconcile or cancel the same attempt).

## Refusals

* submodules (a gitlink) and Git LFS attributes;
* absolute or escaping symlinks, and anything but regular files and symlinks;
* a worktree whose selection, `HEAD`, Git index or captured bytes change during capture;
* a capture target that is not empty, and an attempt id that already exists;
* an executor whose host key, account, uid, root or toolchain does not match its declaration;
* credential and agent-state paths, including explicit `--extra-path` inputs.
* reusing one workspace from two concurrent attempts, overwriting a managed source that changed on
  the executor, removing retained output to make room for new source, symlinked workspace state, and
  pruning an attempt or workspace whose lease is not terminal.

Generated inputs that a project's build does not reproduce can be named with `--extra-path`; they
are explicit, not a second ignore policy.

## Limits

Worktree isolation is not an OS security boundary. Untrusted repository code needs an execution
account and sandbox appropriate to that risk. A name-based credential boundary does not prove that
no semantic secret exists under an ordinary filename. The tool does not enforce that the caller is
the only writer; it detects changes during the capture window. A duplicate id prevents a second
dispatch of the same attempt, not two attempts with different ids performing the same external
effect.

A native managed-worktree child inheriting its parent's dirty, untracked, deleted or executable
state is not an accepted source handoff. Until a verified checkpoint or explicit source protocol
exists, that path is unproven and must not be described as carrying the parent's live input;
capture the intended source through `remote-exec` instead.

## Observed warm-workspace timing

`apps/remote-exec/tests/bench_workspace.py` runs a generic 80-file fixture whose build step is a
mtime comparison with a 0.4 s simulated compile. On `cld-ops-01` with the local fixture transport it
measured cold 2.76 s, unchanged repeat 2.18 s, and one-source-change 2.65 s; the repeat build was the
only HIT. These are local measurements of capture, transfer, reconciliation and supervision, not a
claim about a particular toolchain or a live SSH executor; re-run the script on the executor class
that matters.

## Declared prerequisites

The gateway installs the dedicated private key from SOPS and the generated inventory. The executor
module declares the non-root account, owned root, authorized public key, lingering user manager and
runtime tools. Enabling the module on a host and delivering the SOPS key is the complete
configuration; activation remains operator-owned. A host that has not enabled the module is not
eligible, even if it is paired or selected elsewhere.
