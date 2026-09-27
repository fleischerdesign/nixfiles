"""Read the CEF binary pinned by the application's own Flatpak manifest."""
import base64
import json
from pathlib import Path
import sys
import tomllib
import yaml

source = Path(sys.argv[1])
flatpak = yaml.safe_load((source / sys.argv[2]).read_text())
module, = [module for module in flatpak['modules'] if module['name'] == 'cef-binaries']
entries = [entry for entry in module['sources'] if 'x86_64' in entry.get('only-arches', [])]
binary, = [entry for entry in entries if entry['type'] == 'archive']
metadata, = [entry for entry in entries if entry.get('dest-filename') == 'archive.json']
archive = json.loads(metadata['contents'])
cargo = tomllib.loads((source / 'Cargo.lock').read_text())
cef, = [package for package in cargo['package'] if package['name'] == 'cef']
version = cef['version'].split('+')[1]
if not archive['name'].startswith(f'cef_binary_{version}+'):
    raise ValueError(f'CEF archive does not match the Rust bindings ({version})')
hash_bytes = bytes.fromhex(binary['sha256'])
if len(hash_bytes) != 32:
    raise ValueError('CEF archive must have a SHA256 hash')
print(json.dumps({
    'url': binary['url'], 'hash': 'sha256-' + base64.b64encode(hash_bytes).decode(),
    'archive': archive,
}))
