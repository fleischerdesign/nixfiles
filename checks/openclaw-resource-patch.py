"""Require drifted gateway/worker contracts to fail before any package file is rewritten."""
import importlib.util
from pathlib import Path
import shutil
import sys
import tempfile

patcher_path, gateway, policy = sys.argv[1:]
spec = importlib.util.spec_from_file_location('resource_patch', patcher_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
source = (Path(gateway) / 'lib/openclaw').resolve()

with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    (root / 'dist/worker').mkdir(parents=True)
    names = ['readSkillBundleTree', 'readPluginControlUiAssets', 'loadPackageIcon', 'resolvePluginArtifactManifests']
    for file in (source / 'dist').iterdir():
        if file.suffix not in ('.js', '.mjs') or not file.is_file():
            continue
        if any(f'function {name}(' in file.read_text() for name in names):
            shutil.copyfile(file, root / 'dist' / file.name)
    shutil.copyfile(source / 'dist/worker/worker.mjs', root / 'dist/worker/worker.mjs')
    worker = root / 'dist/worker/worker.mjs'
    # A missing embedded-reader signature must not leave the gateway half-patched.
    original_worker = worker.read_text()
    for altered in [
        original_worker.replace('function readSkillBundleTree(', 'function changedSkillReader(', 1),
        original_worker.replace('hardlinks:`reject`', 'hardlinks:`allow`'),
    ]:
        worker.write_text(altered)
        before = {file: file.read_bytes() for file in root.rglob('*') if file.is_file()}
        try:
            module.patch(root, policy)
        except ValueError:
            pass
        else:
            raise AssertionError('Expected changed worker contract to fail packaging')
        assert before == {file: file.read_bytes() for file in root.rglob('*') if file.is_file()}
        assert not (root / 'dist/nix-resource-policy.mjs').exists()
print('Expected resource-reader contract drift to fail before partial gateway/worker changes: verified')
