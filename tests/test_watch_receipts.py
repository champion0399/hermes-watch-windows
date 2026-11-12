"""Device-free tests for verified install receipts and read-only Watch Lookup."""
import argparse
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import sys
import tempfile
from types import ModuleType
import unittest
from unittest.mock import AsyncMock, MagicMock, patch


HELPER = Path(__file__).resolve().parents[1] / 'watch-device-helper/watch_device.py'
# Stub imports before loading: these tests never import a real device connection.
stubs = {}
for name, attribute in (
    ('pymobiledevice3.services.installation_proxy', 'InstallationProxyService'),
    ('pymobiledevice3.services.streaming_zip_conduit', 'StreamingZipConduitService'),
    ('watch_connection', 'WatchConnection'),
):
    module = ModuleType(name)
    setattr(module, attribute, MagicMock())
    stubs[name] = module
with patch.dict(sys.modules, stubs):
    spec = importlib.util.spec_from_file_location('watch_receipt_helper', HELPER)
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)


class WatchReceiptTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.app = self.root / 'Test.app'
        self.app.mkdir()
        self.info = {'WKApplication': True, 'CFBundleSupportedPlatforms': ['WatchOS'],
                     'CFBundleIdentifier': 'com.example.watch',
                     'CFBundleShortVersionString': '2.1', 'CFBundleVersion': '42'}
        (self.app / 'Info.plist').write_bytes(plistlib.dumps(self.info))
        self.args = argparse.Namespace(install=self.app, receipt=self.root / 'receipt.json',
                                      inspect_bundle=None, inspect_output=None,
                                      state_directory=self.root, pair=False,
                                      device_info=None, reveal_developer_mode=False)
        self.watch = MagicMock()
        self.watch.all_values = {'UniqueDeviceID': 'MOCK-WATCH',
                                 'PairRecord': 'private-pairing-fixture'}
        self.watch.get_developer_mode_status = AsyncMock(return_value=True)
        self.watch.start_lockdown_service = AsyncMock()
        self.conduit = MagicMock()
        self.conduit.install = AsyncMock()
        self.installer = MagicMock()
        self.sender = AsyncMock()
        self.installer.service.send_recv_plist = self.sender
        self.app_metadata = dict(self.info, Path='/private/apps/Test.app')
        self.lookup(self.app_metadata)
        for name, instance in (('WatchConnection', self.watch),
                               ('StreamingZipConduitService', self.conduit),
                               ('InstallationProxyService', self.installer)):
            factory = MagicMock()
            factory.return_value.__aenter__ = AsyncMock(return_value=instance)
            factory.return_value.__aexit__ = AsyncMock(return_value=False)
            patcher = patch.object(helper, name, factory)
            patcher.start()
            self.addCleanup(patcher.stop)
            setattr(self, name, factory)
        self.output = io.StringIO()
        capture = contextlib.redirect_stdout(self.output)
        capture.__enter__()
        self.addCleanup(capture.__exit__, None, None, None)

    def lookup(self, app):
        self.sender.return_value = {'LookupResult': {} if app is None else {'com.example.watch': app}}

    def read_json(self, path):
        return json.loads(path.read_text(encoding='utf-8'))

    async def test_install_writes_flat_verified_receipt(self):
        await helper.main(self.args)
        self.assertEqual(self.read_json(self.args.receipt), {
            'udid': 'MOCK-WATCH', 'bundle_id': 'com.example.watch', 'version': '2.1',
            'build': '42', 'path': '/private/apps/Test.app', 'found': True,
            'installed_verified': True})
        self.conduit.install.assert_awaited_once()
        self.sender.assert_awaited_once_with({
            'Command': 'Lookup', 'ClientOptions': {'BundleIDs': ['com.example.watch']}})
        self.assertNotIn('private-pairing-fixture', self.output.getvalue())
        self.assertNotIn('MOCK-WATCH', self.output.getvalue())

    async def test_missing_app_fails_without_receipt(self):
        self.lookup(None)
        with self.assertRaisesRegex(RuntimeError, 'lookup failed'):
            await helper.main(self.args)
        self.assertFalse(self.args.receipt.exists())

    async def test_each_version_mismatch_fails_without_receipt(self):
        for field in ('CFBundleShortVersionString', 'CFBundleVersion'):
            with self.subTest(field=field):
                self.lookup(dict(self.app_metadata, **{field: 'wrong'}))
                with self.assertRaisesRegex(RuntimeError, field + ' does not match'):
                    await helper.main(self.args)
                self.assertFalse(self.args.receipt.exists())

    async def test_missing_device_version_fails_explicitly(self):
        for field in ('CFBundleShortVersionString', 'CFBundleVersion'):
            with self.subTest(field=field):
                app = dict(self.app_metadata)
                del app[field]
                self.lookup(app)
                with self.assertRaisesRegex(RuntimeError, 'missing a valid ' + field):
                    await helper.main(self.args)
                self.assertFalse(self.args.receipt.exists())

    async def test_existing_receipt_is_never_replaced(self):
        self.args.receipt.write_text('keep-existing', encoding='utf-8')
        with self.assertRaises(FileExistsError):
            await helper.main(self.args)
        self.assertEqual(self.args.receipt.read_text(), 'keep-existing')

    async def test_conduit_failure_does_not_lookup_or_write(self):
        self.conduit.install.side_effect = RuntimeError('mock install failed')
        with self.assertRaisesRegex(RuntimeError, 'mock install failed'):
            await helper.main(self.args)
        self.sender.assert_not_awaited()
        self.assertFalse(self.args.receipt.exists())

    async def test_original_install_without_receipt(self):
        del self.args.receipt
        await helper.main(self.args)
        self.conduit.install.assert_awaited_once()
        self.assertFalse((self.root / 'receipt.json').exists())

    async def inspect(self):
        self.args.install = None
        self.args.receipt = None
        self.args.inspect_bundle = 'com.example.watch'
        self.args.inspect_output = self.root / 'inspect.json'
        self.watch.get_developer_mode_status.return_value = False
        await helper.main(self.args)
        self.StreamingZipConduitService.assert_not_called()
        self.watch.start_lockdown_service.assert_not_awaited()
        return self.read_json(self.args.inspect_output)

    async def test_inspect_found_is_read_only_and_unverified(self):
        metadata = await self.inspect()
        self.assertTrue(metadata['found'])
        self.assertFalse(metadata['installed_verified'])
        self.assertEqual(metadata['build'], '42')
        self.sender.assert_awaited_once_with({
            'Command': 'Lookup', 'ClientOptions': {'BundleIDs': ['com.example.watch']}})

    async def test_inspect_missing_has_flat_null_identity(self):
        self.lookup(None)
        self.assertEqual(await self.inspect(), {
            'udid': 'MOCK-WATCH', 'bundle_id': 'com.example.watch',
            'version': None, 'build': None, 'path': None,
            'found': False, 'installed_verified': False})

    async def test_inspect_missing_version_is_null(self):
        self.lookup({})
        metadata = await self.inspect()
        self.assertTrue(metadata['found'])
        self.assertIsNone(metadata['version'])
        self.assertIsNone(metadata['build'])
        self.assertIsNone(metadata['path'])

    async def test_lookup_error_or_malformed_response_fails(self):
        for result in ({'Error': 'fixture-secret'}, {}, {'LookupResult': []}):
            with self.subTest(result=result):
                self.sender.return_value = result
                with self.assertRaises(RuntimeError) as error:
                    await helper.main(self.args)
                self.assertNotIn('fixture-secret', str(error.exception))
                self.assertFalse(self.args.receipt.exists())

    async def test_original_device_info(self):
        self.args.install = None
        self.args.device_info = self.root / 'device.json'
        await helper.main(self.args)
        self.assertEqual(self.read_json(self.args.device_info),
                         {'udid': 'MOCK-WATCH', 'name': 'Apple Watch'})
        self.InstallationProxyService.assert_not_called()


class ArgumentTests(unittest.TestCase):
    def test_invalid_argument_pairs_exit_before_connection(self):
        for args in (['--receipt', 'out.json'], ['--inspect-bundle', 'com.example.watch'],
                     ['--inspect-output', 'out.json'],
                     ['--inspect-bundle', 'com.example.watch', '--inspect-output', 'out.json',
                      '--install', 'Test.app']):
            with self.subTest(args=args), patch.object(sys, 'argv', ['watch_device.py'] + args), \
                    patch.object(helper, 'WatchConnection') as connection, \
                    contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as error:
                    helper.run()
                self.assertEqual(error.exception.code, 2)
                connection.assert_not_called()


if __name__ == '__main__':
    unittest.main()
