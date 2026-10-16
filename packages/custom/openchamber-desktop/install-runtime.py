"""Copy the web server's runtime dependency closure, preserving Node resolution."""

import json
from pathlib import Path
import shutil
import sys

root = Path.cwd()
destination = Path(sys.argv[1])
visited = set()


def resolve(name, parent):
    for directory in (parent, *parent.parents):
        candidate = directory / "node_modules" / name
        if (candidate / "package.json").is_file():
            return candidate
        if directory == root:
            break
    return None


def install(package):
    target = destination / package.relative_to(root)
    if package.is_symlink():
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.is_symlink():
            target.symlink_to(package.readlink())
        package = package.resolve()
        target = destination / package.relative_to(root)
    if package in visited:
        return
    visited.add(package)
    manifest = json.loads((package / "package.json").read_text())
    shutil.copytree(package, target, symlinks=True, ignore=shutil.ignore_patterns("node_modules"))
    optional = manifest.get("optionalDependencies", {})
    dependencies = {**manifest.get("dependencies", {}), **optional}
    peers = manifest.get("peerDependencies", {})
    for name in sorted(dependencies.keys() | peers.keys()):
        # Like upstream's Electron package, omit the Bun-only PTY backend.
        if name == "bun-pty":
            continue
        dependency = resolve(name, package)
        if dependency is None:
            if name in optional or name in peers:
                continue
            raise RuntimeError(f"Missing runtime dependency {name} of {manifest['name']}")
        install(dependency)


install(root / "node_modules/@openchamber/web")
# The desktop bundle leaves node-pty external as well as the web server.
install(root / "node_modules/node-pty")
# Frontend sources and development-only files are not runtime resources.
web = destination / "packages/web"
for name in ("src", "public", "dist", "scripts", "test"):
    shutil.rmtree(web / name, ignore_errors=True)
pty = destination / "node_modules/node-pty"
# Ship only our freshly compiled addon, never npm's foreign prebuilds.
shutil.rmtree(pty / "prebuilds", ignore_errors=True)
shutil.rmtree(pty / "build/Release/obj.target", ignore_errors=True)
print(f"Installed {len(visited)} runtime packages")
