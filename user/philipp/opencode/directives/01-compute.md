# Where compute-heavy work runs

When the current workspace has a Fleet project configured and `fleet_hosts` lists a suitable
node, run CPU- or memory-heavy work on that node instead of on the control-plane host. This
covers Nix builds and `nix flake check`, Rust/Cargo and other compiler builds, large test
suites, and media processing.

Prefer `hom-wrk-01` (8 cores, 46 GB) or `mob-nb-01`; choose only from what `fleet_hosts`
actually reports. Use `fleet_run` with `sync: auto`. Long-running work uses `background: true`
and is followed with `fleet_jobs` / `fleet_job_status`. Run the Nix gate serially
(`--max-jobs 1`) on the target.

A projectless OpenChamber chat uses the configured default workspace. If none is set, use
`target: scratch` for work without a source tree, and ask which project is meant for source-tree
work. Do not set a global default from a chat.

Do not offload a command whose workspace transfer costs more than the command itself. If no
suitable Fleet host is configured or reachable, say so and defer the heavy step rather than
silently loading `cld-ops-01` or `hom-srv-01`.

Report the worker, the tested revision or replica generation where available, the command and the
final status. A job ID is not a result; a run from an earlier revision is not evidence for the
current one.
