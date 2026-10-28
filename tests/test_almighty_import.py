import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('hardware_build', Path(__file__).resolve().parents[1] / 'scripts/build_ugreenctl.py')
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


class ImportTests(unittest.TestCase):
    def test_local_build_uses_explicit_upstream_root(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / 'snapshot'
            source.mkdir()
            output = root / 'output'
            output.mkdir()
            lock = {'source_type': 'local-artifact', 'artifact_path': 'snapshot',
                    'archive': 'a.tar.gz', 'manifest': 'a.json'}
            for name in ('a.tar.gz', 'a.json', 'SHA256SUMS'):
                (source / name).write_bytes(b'\x00\xfffixture')
            with patch.object(build, 'SOURCE', root):
                build.download_assets(lock, output)
            self.assertEqual((output / 'a.tar.gz').read_bytes(), b'\x00\xfffixture')

    def test_local_build_rejects_path_escape(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            with patch.object(build, 'SOURCE', root):
                with self.assertRaisesRegex(ValueError, 'escapes source root'):
                    build.download_assets({'source_type': 'local-artifact',
                                           'artifact_path': '../outside'}, root)

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        elf = bytearray(64)
        elf[:7] = b'\x7fELF\x02\x01\x01'
        elf[16:18] = (3).to_bytes(2, 'little')
        elf[18:20] = (62).to_bytes(2, 'little')
        names = [*(f'usr/local/bin/{p}' for p in build.PROGRAMS), *(f'usr/local/lib/ugreenctl/models/{m}.so' for m in build.MODELS)]
        self.files = {name: bytes(elf) for name in names}
        self.files['usr/local/share/doc/ugreenctl/LICENSE'] = b'notice'

    def bundle(self, extra=None):
        manifest = dict(package='fixture', architecture='x86_64', branch='Almighty', status='experimental', files=[dict(path=n, size=len(d), sha256=build.digest(d)) for n, d in self.files.items()])
        raw = json.dumps(manifest).encode()
        (self.root / 'manifest.json').write_bytes(raw)
        with tarfile.open(self.root / 'archive.tar.gz', 'w:gz') as archive:
            for name, data in [*self.files.items(), ('manifest.json', raw), *((extra,) if extra else ())]:
                member = tarfile.TarInfo('fixture/' + name)
                member.size = len(data)
                archive.addfile(member, io.BytesIO(data))
        lock = dict(archive='archive.tar.gz', manifest='manifest.json', tag='preview', commit='a' * 40)
        for key in ('archive', 'manifest'):
            lock[key + '_sha256'] = build.digest((self.root / lock[key]).read_bytes())
        sums = ''.join(f'{lock[k + "_sha256"]}  {lock[k]}\n' for k in ('archive', 'manifest')).encode()
        (self.root / 'SHA256SUMS').write_bytes(sums)
        lock['checksums_sha256'] = build.digest(sums)
        return lock

    def test_import_replaces_all_programs_and_records_published_payload(self):
        lock = self.bundle()
        manifest, files = build.validate_release(self.root, lock)
        server = self.root / 'server'
        (server / 'bin').mkdir(parents=True)
        (server / 'bin/ugreen_leds_cli').write_bytes(b'old LED')
        build.install_release(manifest, files, lock, server)
        receipt = json.loads((server / 'lib/ugreenctl/build-info.json').read_text())
        self.assertEqual(len(receipt['files']), 14)
        self.assertEqual(receipt['release_tag'], 'preview')
        for p in build.PROGRAMS:
            self.assertEqual((server / 'bin' / p).read_bytes(), self.files[f'usr/local/bin/{p}'])
        self.assertEqual((server / 'lib/ugreenctl/upstream/LICENSE').read_bytes(), b'notice')

    def test_branch_download_pins_commit_and_preserves_binary_bytes(self):
        lock = self.bundle()
        lock.update(source_type='git-artifact', repository='owner/repo',
                    artifact_commit='b' * 40, artifact_path='artifacts/snapshot')
        expected = b'\x00\xff\r\nraw'
        with patch.object(build.urllib.request, 'urlopen', side_effect=lambda *a, **k: io.BytesIO(expected)) as fetch:
            build.download_assets(lock, self.root)
        self.assertEqual(fetch.call_count, 3)
        for call in fetch.call_args_list:
            self.assertIn('/' + 'b' * 40 + '/artifacts/snapshot/', call.args[0])
        self.assertEqual((self.root / lock['archive']).read_bytes(), expected)

    def test_wrong_architecture(self):
        name = 'usr/local/bin/ugreen_leds_cli'
        data = bytearray(self.files[name]); data[18:20] = (183).to_bytes(2, 'little')
        self.files[name] = bytes(data)
        with self.assertRaisesRegex(ValueError, 'Wrong ELF'):
            build.validate_release(self.root, self.bundle())

    def test_missing_plugin(self):
        del self.files['usr/local/lib/ugreenctl/models/dxp2800.so']
        with self.assertRaisesRegex(ValueError, 'Missing required'):
            build.validate_release(self.root, self.bundle())

    def test_tampered_archive(self):
        lock = self.bundle()
        with (self.root / 'archive.tar.gz').open('ab') as f: f.write(b'tampered')
        with self.assertRaisesRegex(ValueError, 'SHA256 mismatch'):
            build.validate_release(self.root, lock)

    def test_unsafe_path(self):
        lock = self.bundle(('../escape', b'bad'))
        with self.assertRaisesRegex(ValueError, 'Unsafe archive'):
            build.validate_release(self.root, lock)

    def test_duplicate_member(self):
        lock = self.bundle(('usr/local/bin/ugreenctl', b'duplicate'))
        with self.assertRaisesRegex(ValueError, 'Duplicate archive'):
            build.validate_release(self.root, lock)

if __name__ == '__main__':
    unittest.main()
