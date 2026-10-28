#!/usr/bin/env python3
"""Import the pinned hardware Release after hash, ELF and isolated CLI validation."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
import shutil
from pathlib import Path, PurePosixPath
import subprocess
import sys
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
SERVER = ROOT / 'App.Native.UGreenLED/app/server'
SOURCE = ROOT.parent / 'UGREEN-NAS-Hardware'
LOCK_FILE = Path(__file__).with_name('hardware-release.json')
PROGRAMS = ('ugreenctl', 'ugreenctl-fand', 'ugreen_leds_cli', 'ugreenctl-ledd')
MODELS = ('dx4600', 'dxp2800', 'dxp4800', 'dxp4800plus', 'dxp4800s', 'dxp480tplus', 'dxp6800pro', 'dxp6800plus', 'dxp6800', 'dxp8800plus')

def digest(data):
    return hashlib.sha256(data).hexdigest()

def checked(path, expected):
    data = path.read_bytes()
    if digest(data) != expected:
        raise ValueError(f'SHA256 mismatch: {path.name}')
    return data

def validate_release(directory, lock):
    checked(directory / lock['archive'], lock['archive_sha256'])
    raw = checked(directory / lock['manifest'], lock['manifest_sha256'])
    sums = checked(directory / 'SHA256SUMS', lock['checksums_sha256']).decode('ascii')
    entries = {line.split()[1].lstrip('*'): line.split()[0] for line in sums.splitlines() if line.strip()}
    for key in ('archive', 'manifest'):
        if entries.get(lock[key]) != lock[key + '_sha256']:
            raise ValueError('Release checksum list mismatch')
    manifest = json.loads(raw)
    if manifest['architecture'] != 'x86_64' or manifest['branch'] != lock.get('branch', 'Almighty'):
        raise ValueError('Expected pinned branch x86_64 release')
    if 'version' in lock and manifest.get('version') != lock['version']:
        raise ValueError('Hardware release version mismatch')
    if 'release_channel' in lock and manifest.get('release_channel') != lock['release_channel']:
        raise ValueError('Hardware release channel mismatch')
    files = {}
    prefix = manifest['package'] + '/'
    with tarfile.open(directory / lock['archive'], 'r:gz') as archive:
        for member in archive:
            path = PurePosixPath(member.name)
            if (not member.name.startswith(prefix) or path.is_absolute() or '..' in path.parts
                    or '\\' in member.name or ':' in member.name or not member.isfile()):
                raise ValueError(f'Unsafe archive member: {member.name}')
            name = member.name[len(prefix):]
            if name in files:
                raise ValueError(f'Duplicate archive member: {name}')
            files[name] = archive.extractfile(member).read()
    if files.get('manifest.json') != raw:
        raise ValueError('Embedded manifest mismatch')
    listed = {item['path'] for item in manifest['files']}
    if set(files) != listed | {'manifest.json'}:
        raise ValueError('Unlisted archive payload')
    for item in manifest['files']:
        data = files.get(item['path'])
        if data is None or len(data) != item['size'] or digest(data) != item['sha256']:
            raise ValueError(f'Payload mismatch: {item["path"]}')
    for name in [*(f'usr/local/bin/{p}' for p in PROGRAMS), *(f'usr/local/lib/ugreenctl/models/{m}.so' for m in MODELS)]:
        if name not in listed:
            raise ValueError(f'Missing required artifact: {name}')
        data = files[name]
        if (len(data) < 64 or data[:7] != b'\x7fELF\x02\x01\x01'
                or int.from_bytes(data[18:20], 'little') != 62
                or int.from_bytes(data[16:18], 'little') not in ((3,) if name.endswith('.so') else (2, 3))):
            raise ValueError(f'Wrong ELF type or architecture: {name}')
    if lock.get('source_type') == 'github-release':
        verification = json.loads(files['usr/local/share/doc/ugreenctl/verification-root.json'])
        if verification.get('source_commit') != lock['commit'] or verification.get('branch') != lock['branch']:
            raise ValueError('Hardware release source commit/branch mismatch')
    return manifest, files

def smoke_test(files, runtime_root, expected_version=None):
    with tempfile.TemporaryDirectory(prefix='almighty-release-') as temporary:
        stage = Path(temporary)
        (stage / 'models').mkdir()
        for program in PROGRAMS:
            p = stage / program
            p.write_bytes(files[f'usr/local/bin/{program}'])
            p.chmod(0o755)
        for model in MODELS:
            (stage / 'models' / f'{model}.so').write_bytes(files[f'usr/local/lib/ugreenctl/models/{model}.so'])
        def run(program, args, expected=0):
            command = [str(stage / program), *args]
            if os.name == 'nt':
                if runtime_root is None:
                    raise ValueError('Windows import requires --runtime-root')
                command = [sys.executable, str(SOURCE / 'tools/testing/run_linux.py'), '--runtime-root', str(runtime_root), *command]
            result = subprocess.run(command, capture_output=True, text=True, timeout=90)
            if result.returncode != expected:
                raise ValueError(f'{program} smoke test failed: {result.stdout} {result.stderr}')
            return result.stdout + result.stderr
        models = run('ugreenctl', ['--plugin-dir', '/work/models' if os.name == 'nt' else str(stage / 'models'), 'models'])
        if set(MODELS) != {line.split()[0] for line in models.splitlines() if line.strip()}:
            raise ValueError('Not all ten plugins loaded')
        if expected_version is not None and run('ugreenctl', ['--version']).strip() != expected_version:
            raise ValueError('Imported CLI version mismatch')
        for command in (['network', 'wol', 'models'], ['power', 'rtc-wake', 'models']):
            profiles = run('ugreenctl', command)
            if '\tDXP8800 Plus\t' not in profiles or '\tDXP6800 Plus\t' not in profiles:
                raise ValueError('Independent wake profiles are missing from imported CLI')
        if '--apply' not in run('ugreen_leds_cli', ['--help']):
            raise ValueError('Unexpected LED compatibility CLI')
        run('ugreenctl-ledd', ['--help'])
        if 'Usage: ugreenctl-fand' not in run('ugreenctl-fand', ['--help'], expected=1):
            raise ValueError('Unexpected fan daemon')

def install_release(manifest, files, lock, server=SERVER):
    record = {'branch': manifest['branch'], 'revision': lock['commit'], 'release_tag': lock['tag'],
              'archive_sha256': lock['archive_sha256'], 'architecture': 'x86_64',
              'status': manifest['status'], 'version': manifest.get('version'),
              'release_channel': manifest.get('release_channel'), 'files': {}}
    if 'local_extension' in manifest:
        record['base_revision'] = lock['commit']
        record['revision'] = 'local-source-sha256:' + digest(
            json.dumps(manifest['local_extension']['source_sha256'], sort_keys=True).encode('utf-8'))
    for key in ('repository', 'source_type', 'artifact_commit', 'artifact_path', 'source_state'):
        if key in lock:
            record[key] = lock[key]
    payloads = {}
    for program in PROGRAMS:
        payloads[f'bin/{program}'] = files[f'usr/local/bin/{program}']
        record['files'][program] = digest(payloads[f'bin/{program}'])
    for model in MODELS:
        name = f'models/{model}.so'
        payloads[f'lib/ugreenctl/{name}'] = files[f'usr/local/lib/ugreenctl/{name}']
        record['files'][name] = digest(payloads[f'lib/ugreenctl/{name}'])
    prefix = 'usr/local/share/doc/ugreenctl/'
    for name, data in files.items():
        if name.startswith(prefix):
            payloads['lib/ugreenctl/upstream/' + name[len(prefix):]] = data
    payloads['lib/ugreenctl/release-manifest.json'] = files['manifest.json']
    payloads['bin/ugreen_leds_cli.sha256'] = (record['files']['ugreen_leds_cli'] + '  ugreen_leds_cli\n').encode('ascii')
    # This directory is entirely managed by the imported manifest. Remove the
    # previous local extension snapshot when replacing it with a full Release.
    upstream = server / 'lib/ugreenctl/upstream'
    boundary = server.resolve()
    old_paths = sorted(upstream.rglob('*'), key=lambda p: len(p.parts), reverse=True)
    for old in old_paths:
        if old.is_symlink() or not old.resolve().is_relative_to(boundary):
            raise ValueError('Unsafe imported upstream path')
        if old.is_file() and old.relative_to(server).as_posix() not in payloads:
            old.unlink()
        elif old.is_dir() and not any(old.iterdir()):
            old.rmdir()
    for name, data in payloads.items():
        target = server / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        target.chmod(0o755 if name.startswith('bin/') and not name.endswith('.sha256') else 0o644)
    for old in (server / 'lib/ugreenctl/models').glob('*.so'):
        if old.stem not in MODELS:
            old.unlink()
    # Written last: incomplete imports fail the packaging receipt check.
    (server / 'lib/ugreenctl/build-info.json').write_text(json.dumps(record, indent=2) + '\n', encoding='utf-8', newline='\n')

def download_assets(lock, directory):
    if lock.get('source_type') == 'local-artifact':
        # Unpublished builds retain normal archive, manifest and payload checks.
        root = SOURCE.resolve()
        source = (root / lock['artifact_path']).resolve()
        if not source.is_relative_to(root):
            raise ValueError('Local hardware artifact escapes source root')
        for name in (lock['archive'], lock['manifest'], 'SHA256SUMS'):
            if Path(name).name != name or '\\' in name:
                raise ValueError('Invalid local artifact filename')
            shutil.copyfile(source / name, directory / name)
    elif lock.get('source_type') == 'git-artifact':
        # Read immutable Git content, never the moving branch head.
        for name in (lock['archive'], lock['manifest'], 'SHA256SUMS'):
            url = f"https://raw.githubusercontent.com/{lock['repository']}/{lock['artifact_commit']}/{lock['artifact_path']}/{name}"
            with urllib.request.urlopen(url, timeout=90) as response:
                data = response.read()
            (directory / name).write_bytes(data)
    else:
        subprocess.run(['gh', 'release', 'download', lock['tag'], '--repo', lock['repository'],
                        '--dir', str(directory), '--pattern', lock['archive'], '--pattern', lock['manifest'],
                        '--pattern', 'SHA256SUMS'], check=True)

def main():
    global SOURCE
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', type=Path, default=SOURCE,
                        help='Upstream checkout for local artifacts and the Windows smoke runner')
    parser.add_argument('--asset-dir', type=Path)
    parser.add_argument('--runtime-root', type=Path)
    parser.add_argument('--check-only', action='store_true')
    args = parser.parse_args()
    SOURCE = args.source_root.resolve()
    if args.runtime_root is None and os.name == 'nt':
        args.runtime_root = SOURCE / 'firmware-inbox/work/almighty-tools'
    lock = json.loads(LOCK_FILE.read_text(encoding='utf-8'))
    with tempfile.TemporaryDirectory(prefix='almighty-download-') as temporary:
        directory = args.asset_dir or Path(temporary)
        if args.asset_dir is None:
            download_assets(lock, directory)
        manifest, files = validate_release(directory, lock)
        smoke_test(files, args.runtime_root, expected_version=lock.get('version'))
        if not args.check_only:
            install_release(manifest, files, lock)
        print(f'Validated {lock["tag"]}: four programs, ten plugins, all manifest payload hashes')

if __name__ == '__main__':
    main()
