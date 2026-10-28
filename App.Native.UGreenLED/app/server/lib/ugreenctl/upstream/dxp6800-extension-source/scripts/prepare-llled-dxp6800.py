"""Compose a local DXP6800 extension without replacing unrelated pinned binaries.

Run after building build-dxp6800. This creates a local input archive for LLLED,
not an FPK or a published release. The base archive remains immutable.
"""
import gzip
import hashlib
import io
import json
from pathlib import Path
import tarfile

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'artifacts/Almighty/2026-10-27-n76-direct'
OUT = ROOT / 'artifacts/Almighty/2026-10-28-dxp6800-local'
NAME = 'ugreenctl-almighty-0.2.0-linux-x86_64-preview'
BASE_SHA = '9827b4f1c0f0f251634bf07041c6ff2f9b6504e5e212c3ff1520174ad95389c1'

def sha(data):
    return hashlib.sha256(data).hexdigest()

def encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + '\n').encode()

def main():
    raw = (BASE / (NAME + '.tar.gz')).read_bytes()
    if sha(raw) != BASE_SHA:
        raise ValueError('Pinned base archive hash mismatch')
    files = {}
    with tarfile.open(fileobj=io.BytesIO(raw), mode='r:gz') as archive:
        for member in archive:
            if not member.isfile() or not member.name.startswith(NAME + '/'):
                raise ValueError('Unexpected base member')
            files[member.name[len(NAME)+1:]] = (archive.extractfile(member).read(), member.mode)
    manifest = json.loads(files.pop('manifest.json')[0])
    for item in manifest['files']:
        if sha(files[item['path']][0]) != item['sha256']:
            raise ValueError('Base manifest mismatch')
    replacements = {'usr/local/lib/ugreenctl/models/dxp6800.so': 'models/dxp6800.so',
                    'usr/local/bin/ugreenctl-fand': 'ugreenctl-fand'}
    for destination, source in replacements.items():
        binary = (ROOT / 'build-dxp6800' / source).read_bytes()
        if binary[:7] != b'\x7fELF\x02\x01\x01' or int.from_bytes(binary[18:20], 'little') != 62:
            raise ValueError('Expected Linux x86_64 ELF')
        files[destination] = (binary, 0o755)
    # Preserve the exact source used for the two extension binaries, separately
    # from the base archive's provenance. Do not claim a clean Git revision.
    sources = {'CMakeLists.txt', 'core/fan_daemon.c', 'models/dxp6800.c',
               'docs/DXP6800_SUPPORT.zh-CN.md', 'docs/FAN_CURVE.md', 'tests/test_thermal_curve.c', 'scripts/prepare-llled-dxp6800.py',
               'tests/test_dxp6800_plugin.c', 'tests/test_it8613_dxp6800.c'}
    for directory in ('fan', 'power', 'superio', 'include'):
        sources.update(p.relative_to(ROOT).as_posix() for p in (ROOT / directory).rglob('*')
                       if p.suffix in ('.c', '.h'))
    source_hashes = {}
    for name in sorted(sources):
        data = (ROOT / name).read_bytes()
        source_hashes[name] = sha(data)
        files['usr/local/share/doc/ugreenctl/dxp6800-extension-source/' + name] = (data, 0o644)
    files['usr/local/share/doc/ugreenctl/docs/DXP6800_SUPPORT.zh-CN.md'] = (
        (ROOT / 'docs/DXP6800_SUPPORT.zh-CN.md').read_bytes(), 0o644)
    files['usr/local/share/doc/ugreenctl/docs/FAN_CURVE.md'] = (
        (ROOT / 'docs/FAN_CURVE.md').read_bytes(), 0o644)
    manifest['local_extension'] = {'id': 'dxp6800-20261028', 'base_archive_sha256': BASE_SHA,
                                  'source_sha256': source_hashes,
                                  'changed_payloads': sorted(replacements),
                                  'physical_validation': 'not-performed'}
    # Base suite records describe the base, not this composed local artifact.
    for key in ('full_suite', 'full_suite_artifacts', 'verification_sha256'):
        if key in manifest:
            manifest['local_extension']['base_' + key] = manifest.pop(key)
    manifest.update(status='experimental-local-dxp6800', verification_complete=False)
    manifest['files'] = [{'path': name, 'size': len(data), 'mode': f'{mode:04o}', 'sha256': sha(data)}
                         for name, (data, mode) in sorted(files.items())]
    manifest_raw = encoded(manifest)
    files['manifest.json'] = (manifest_raw, 0o644)
    buffer = io.BytesIO()
    with gzip.GzipFile(fileobj=buffer, mode='wb', mtime=0, filename='') as compressed:
        with tarfile.open(fileobj=compressed, mode='w') as archive:
            for name, (data, mode) in sorted(files.items()):
                member = tarfile.TarInfo(NAME + '/' + name)
                member.size, member.mode = len(data), mode
                archive.addfile(member, io.BytesIO(data))
    OUT.mkdir(parents=True, exist_ok=True)
    assets = {NAME + '.tar.gz': buffer.getvalue(), NAME + '.manifest.json': manifest_raw}
    assets['SHA256SUMS'] = ''.join(f'{sha(data)}  {name}\n' for name, data in assets.items()).encode()
    for name, data in assets.items():
        (OUT / name).write_bytes(data)
    print(OUT)

if __name__ == '__main__':
    main()
