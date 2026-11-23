"""Add OpenCode's provider.go-limit to both OpenChamber failover boundaries.

The server-side classifier and the generated OpenCode plugin each carry their own
LIMIT_ERROR_TYPES set. Missing either one silently prevents OpenCode Go quota
failover, so this patch is deliberately exact and fails loudly when upstream
changes the shape.
"""

from pathlib import Path
import sys


POLICY = Path("packages/web/server/lib/limit-failover/policy.ts")
RUNTIME = Path("packages/web/server/lib/limit-failover/runtime.ts")

POLICY_NEEDLE = """  'provider.rate-limit',
]);"""
POLICY_PATCHED = """  'provider.rate-limit',
  'provider.go-limit',
]);"""

RUNTIME_NEEDLE = (
    'const LIMIT_ERROR_TYPES = new Set(["provider.quota", "provider.free-limit", '
    '"provider.budget-limit", "provider.model-budget-limit", "provider.rate-limit"])'
)
RUNTIME_PATCHED = (
    'const LIMIT_ERROR_TYPES = new Set(["provider.quota", "provider.free-limit", '
    '"provider.budget-limit", "provider.model-budget-limit", "provider.rate-limit", '
    '"provider.go-limit"])'
)


def patch(path: Path, needle: str, replacement: str) -> None:
    text = path.read_text()
    if replacement in text:
        return
    count = text.count(needle)
    if count != 1:
        raise SystemExit(
            f"{path}: expected exactly one failover type block, found {count}. "
            "OpenChamber's limit-failover shape changed; review the patch."
        )
    path.write_text(text.replace(needle, replacement, 1))


def main(root: Path) -> None:
    policy = root / POLICY
    runtime = root / RUNTIME
    patch(policy, POLICY_NEEDLE, POLICY_PATCHED)
    patch(runtime, RUNTIME_NEEDLE, RUNTIME_PATCHED)
    for path in (policy, runtime):
        if "provider.go-limit" not in path.read_text():
            raise SystemExit(f"{path}: provider.go-limit is missing after patching")
    print("OpenChamber limit failover includes provider.go-limit in both boundaries")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: patch-limit-failover.py <openchamber-source>")
    main(Path(sys.argv[1]))
