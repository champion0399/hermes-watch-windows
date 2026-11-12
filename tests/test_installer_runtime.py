import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch
import zipfile

SPEC = importlib.util.spec_from_file_location('runtime', Path(__file__).resolve().parents[1] / 'lib/hermes_runtime.py')
runtime = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runtime)
ROOT = 'Payload/HermesCompanion.app/Watch/HermesEnabler2.app'
GROUP = 'group.com.abcde.hermes'


def ipa(path, marker=runtime.OLD_GROUP, extra=None):
    info = {'WKApplication': True, 'CFBundleSupportedPlatforms': ['WatchOS'], 'CFBundleExecutable': 'HermesEnabler2'}
    with zipfile.ZipFile(path, 'w') as z:
        z.writestr('Payload/HermesCompanion.app/Info.plist', plistlib.dumps({'CFBundleExecutable': 'HermesCompanion'}))
        z.writestr(ROOT + '/Info.plist', plistlib.dumps(info))
        z.writestr(ROOT + '/HermesEnabler2', b'MACHO' + marker)
        z.writestr(ROOT + '/Assets.car', b'assets')
        if extra:
            z.writestr(*extra)


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.source = self.root / 'upstream.ipa'
        ipa(self.source)

    def test_patch_exact_length(self):
        out = self.root / 'patched.ipa'
        result = runtime.patch(self.source, out, GROUP)
        self.assertEqual(result['replacements'], 1)
        with zipfile.ZipFile(out) as z:
            self.assertEqual(z.read(ROOT + '/HermesEnabler2'), b'MACHO' + GROUP.encode())

    def test_reject_short_default_user_group(self):
        with self.assertRaises(ValueError): runtime.group_bytes('group.com.user.hermes')

    def test_reject_non_ascii_group(self):
        with self.assertRaises(ValueError): runtime.group_bytes('group.com.中文.hermes')

    def test_reject_no_marker_without_overwrite(self):
        ipa(self.source, b'changed-upstream')
        out = self.root / 'patched.ipa'; out.write_bytes(b'previous-good-ipa')
        with self.assertRaises(ValueError): runtime.patch(self.source, out, GROUP)
        self.assertEqual(out.read_bytes(), b'previous-good-ipa')

    def test_idempotent_patch(self):
        ipa(self.source, GROUP.encode())
        self.assertEqual(runtime.patch(self.source, self.root / 'patched.ipa', GROUP)['replacements'], 0)

    def test_reject_same_input_output(self):
        with self.assertRaises(ValueError): runtime.patch(self.source, self.source, GROUP)

    def test_extract_selects_watch_instead_of_parent(self):
        app = Path(runtime.extract_watch(self.source, self.root / 'extract'))
        self.assertEqual(app.name, 'HermesEnabler2.app')
        self.assertTrue((app / 'Info.plist').exists())
        self.assertFalse((self.root / 'extract/Payload/HermesCompanion.app/Info.plist').exists())
        self.assertTrue((app / 'HermesEnabler2').stat().st_mode & 0o111)

    def test_extract_rejects_nonempty_destination(self):
        dest = self.root / 'extract'; dest.mkdir(); (dest / 'keep').touch()
        with self.assertRaises(ValueError): runtime.extract_watch(self.source, dest)

    def test_reject_zip_traversal(self):
        ipa(self.source, extra=('../../escape', b'bad'))
        with self.assertRaises(ValueError): runtime.extract_watch(self.source, self.root / 'extract')
        self.assertFalse((self.root.parent / 'escape').exists())

    def test_reject_html_download(self):
        self.source.write_bytes(b'<html>404</html>')
        with self.assertRaises(zipfile.BadZipFile): runtime.extract_watch(self.source, self.root / 'extract')

    def release(self, **changes):
        data = self.source.read_bytes()
        asset = {'name': 'HermesEnabler.ipa', 'size': len(data), 'browser_download_url': 'https://github.com/pookjw/HermesEnabler/releases/download/1.5.1/HermesEnabler.ipa', 'digest': 'sha256:' + hashlib.sha256(data).hexdigest()}
        asset.update(changes)
        return {'tag_name': '1.5.1', 'assets': [asset]}, data

    def test_download_hash_verified(self):
        release, data = self.release()
        with patch.object(runtime, 'fetch', side_effect=[io.BytesIO(json.dumps(release).encode()), io.BytesIO(data)]):
            out = self.root / 'latest.ipa'
            self.assertEqual(runtime.latest(out)['tag'], '1.5.1')
            self.assertEqual(out.read_bytes(), data)

    def test_download_bad_digest_preserves_previous_file(self):
        release, data = self.release(digest='sha256:WRONG')
        out = self.root / 'latest.ipa'; out.write_bytes(b'previous')
        with patch.object(runtime, 'fetch', side_effect=[io.BytesIO(json.dumps(release).encode()), io.BytesIO(data)]):
            with self.assertRaises(ValueError): runtime.latest(out)
        self.assertEqual(out.read_bytes(), b'previous')

    def test_download_size_mismatch(self):
        release, data = self.release(size=1)
        with patch.object(runtime, 'fetch', side_effect=[io.BytesIO(json.dumps(release).encode()), io.BytesIO(data)]):
            with self.assertRaises(ValueError): runtime.latest(self.root / 'latest.ipa')

    def test_ambiguous_release_assets(self):
        release, data = self.release(); release['assets'] *= 2
        with patch.object(runtime, 'fetch', return_value=io.BytesIO(json.dumps(release).encode())):
            with self.assertRaises(ValueError): runtime.latest(self.root / 'latest.ipa')

    def test_unsupported_release_url(self):
        with self.assertRaises(ValueError): runtime.fetch('http://github.com/fake')


if __name__ == '__main__': unittest.main(verbosity=2)
