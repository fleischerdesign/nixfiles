# Where compute-heavy work runs

When the current workspace has a Fleet project configured and `fleet_hosts` lists a suitable
node, run CPU- or memory-heavy work on that node instead of on the control-plane host. This
covers Nix builds and `nix flake check`, Rust/Cargo and other compiler builds, large test
suites, and media processing.

Prefer `hom-wrk-01` (8 cores, 46 GB) or `mob-nb-01`; choose only from what `fleet_hosts`
actually reports. Use `fleet_run` with `sync: auto`. Long-running work uses `background: true`
and is followed with `fleet_jobs` / `fleet_job_status`. Run the Nix gate serially
(`--max-jobs 1`) on the target.

A projectless OpenChamber chat uses the configured default workspace. If Fleet reports that no
default is set, configure it once with `fleet default /home/philipp/dev/nixfiles`; do not invent
a per-chat workspace.

Do not offload a command whose workspace transfer costs more than the command itself. If no
suitable Fleet host is configured or reachable, say so and defer the heavy step rather than
silently loading `cld-ops-01` or `hom-srv-01`.
