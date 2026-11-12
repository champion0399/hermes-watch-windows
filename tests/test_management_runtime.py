"""Management operations use synthetic IPA/profile fixtures, without device access."""
import contextlib
from datetime import datetime, timedelta, timezone
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

SPEC = importlib.util.spec_from_file_location('management_runtime', Path(__file__).resolve().parents[1] / 'lib/hermes_runtime.py')
runtime = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runtime)
ROOT = 'Payload/Companion.app/Watch/TestWatch.app'
GROUP = 'group.com.abcde.hermes'
OTHER = 'group.com.fghij.hermes'


def make_ipa(path, groups=None, profile=True, cms=False, dates=None, devices=None, marker=None, extra=None,
             application_id='TEAM123.org.example.watch', profile_uuid='profile-uuid'):
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    data = {'CreationDate': now - timedelta(hours=2), 'ExpirationDate': now + timedelta(hours=24),
            'UUID': profile_uuid, 'ProvisionedDevices': ['watch-123'] if devices is None else devices,
            'Entitlements': {'com.apple.security.application-groups': [GROUP] if groups is None else groups,
                             'application-identifier': application_id}}
    if dates:
        data.update(dates)
    metadata = {'WKApplication': True, 'CFBundleSupportedPlatforms': ['WatchOS'],
                'CFBundleExecutable': 'WatchExe', 'CFBundleIdentifier': 'org.example.watch',
                'CFBundleShortVersionString': '1.2', 'CFBundleVersion': '34'}
    with zipfile.ZipFile(path, 'w') as z:
        z.writestr(ROOT + '/Info.plist', plistlib.dumps(metadata))
        z.writestr(ROOT + '/WatchExe', b'MACHO' + (GROUP.encode() if marker is None else marker))
        if profile:
            payload = plistlib.dumps(data)
            z.writestr(ROOT + '/embedded.mobileprovision', b'CMS-header' + payload + b'CMS-trailer' if cms else payload)
        if extra:
            z.writestr(*extra)


class ManagementRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.conf = self.root / 'hermes-watch.conf'
        self.signed = self.root / 'hermes-signed.ipa'
        make_ipa(self.signed)

    def read_conf(self, text):
        self.conf.write_text(text, encoding='utf-8')
        return runtime.config_read(self.conf)['values']

    def test_static_config_shell_quotes_comments_and_escaped_spaces(self):
        values = self.read_conf('# comment\nGROUP_ID=' + GROUP + '\nAPP_NAME="Test Watch.app"\n'
                                'SIGNED_IPA=/tmp/a\\ b.ipa # saved path\nWATCH_UDID=\nUPSTREAM_TAG=\'v1\'\n')
        self.assertEqual(values['SIGNED_IPA'], '/tmp/a b.ipa')
        self.assertEqual(values['APP_NAME'], 'Test Watch.app')
        self.assertEqual(values['WATCH_UDID'], '')

    def test_shell_execution_and_expansions_rejected_without_effects(self):
        sentinel = self.root / 'executed'
        attacks = ['APP_NAME=$(touch ' + str(sentinel) + ')', 'APP_NAME=`whoami`',
                   'APP_NAME="$HOME"', 'APP_NAME=${HOME}', 'APP_NAME=$((1+2))',
                   'APP_NAME=ok;touch x', 'APP_NAME=ok && echo bad', 'APP_NAME=*.ipa',
                   'APP_NAME=~/test', 'APP_NAME=<(echo bad)', 'export GROUP_ID=' + GROUP,
                   'UNKNOWN=value', 'APP_NAME="unterminated', 'APP_NAME=foo\\\nbar',
                   'APP_NAME=foo\0bar', 'APP_NAME="first\nsecond"']
        for attack in attacks:
            with self.subTest(attack=attack), self.assertRaises(ValueError):
                self.read_conf('GROUP_ID=' + GROUP + '\n' + attack + '\n')
        self.assertFalse(sentinel.exists())

    def test_empty_missing_invalid_group_rejected(self):
        for text in ('', 'WATCH_UDID=watch', 'GROUP_ID=', 'GROUP_ID=group.short'):
            with self.subTest(text=text), self.assertRaises(ValueError):
                self.read_conf(text)

    def test_path_control_characters_rejected(self):
        for path in ('bad\0path', 'bad\npath', 'bad\rpath'):
            for operation in (runtime.config_read, runtime.config_import, runtime.info):
                with self.subTest(path=path, operation=operation), self.assertRaises(ValueError):
                    operation(path)

    def test_import_uses_real_watch_profile_and_leaves_disk_unchanged(self):
        make_ipa(self.root / 'hermes-grouped.ipa', profile=False)
        before = set(self.root.iterdir())
        values = runtime.config_import(self.root)['values']
        self.assertEqual(values['GROUP_ID'], GROUP)
        self.assertEqual(values['WATCH_UDID'], '')
        self.assertEqual(values['APP_NAME'], 'TestWatch.app')
        self.assertEqual(values['SIGNED_IPA'], str(self.signed.resolve()))
        self.assertTrue(values['GROUPED_IPA'].endswith('hermes-grouped.ipa'))
        self.assertEqual(set(self.root.iterdir()), before)

    def test_import_canonical_signed_preferred_over_history(self):
        make_ipa(self.root / 'old-signed.ipa', groups=[OTHER])
        self.assertEqual(runtime.config_import(self.root)['values']['GROUP_ID'], GROUP)

    def test_import_fallback_and_same_group_candidates(self):
        self.signed.rename(self.root / 'first-signed.ipa')
        make_ipa(self.root / 'second-signed.ipa', cms=True)
        self.assertEqual(runtime.config_import(self.root)['values']['GROUP_ID'], GROUP)

    def test_import_rejects_multiple_valid_groups_or_profiles(self):
        make_ipa(self.signed, groups=[GROUP, OTHER])
        with self.assertRaises(ValueError): runtime.config_import(self.root)
        self.signed.unlink()
        make_ipa(self.root / 'one-signed.ipa')
        make_ipa(self.root / 'two-signed.ipa', groups=[OTHER])
        with self.assertRaises(ValueError): runtime.config_import(self.root)

    def test_import_ignores_invalid_group_but_requires_one_valid_group(self):
        make_ipa(self.signed, groups=['group.short', GROUP, GROUP])
        self.assertEqual(runtime.config_import(self.root)['values']['GROUP_ID'], GROUP)
        make_ipa(self.signed, groups=['group.short'])
        with self.assertRaises(ValueError): runtime.config_import(self.root)

    def test_import_missing_profile_or_signed_and_existing_conf(self):
        make_ipa(self.signed, profile=False, extra=('Payload/Companion.app/embedded.mobileprovision', plistlib.dumps({'decoy': GROUP})))
        with self.assertRaises(KeyError): runtime.config_import(self.root)
        self.signed.unlink()
        with self.assertRaises(ValueError): runtime.config_import(self.root)
        self.conf.touch()
        with self.assertRaises(ValueError): runtime.config_import(self.root)

    def test_verify_xml_and_cms_structure_without_signature_claim(self):
        for cms in (False, True):
            make_ipa(self.signed, cms=cms)
            result = runtime.verify_signed(self.signed, GROUP, 'watch-123')
            self.assertEqual(result['bundle_id'], 'org.example.watch')
            self.assertEqual(result['profile_uuid'], 'profile-uuid')
            self.assertGreater(result['remaining_hours'], 23)
            self.assertLessEqual(result['remaining_hours'], 24)
            self.assertEqual(result['validation'], 'structure-only')
            self.assertFalse(result['cms_signature_verified'])
            self.assertEqual(runtime.profile(self.signed)['groups'], [GROUP])

    def test_verify_requires_requested_group_and_watch(self):
        for group, device in ((OTHER, 'watch-123'), (GROUP, 'other-watch'), (GROUP, '')):
            with self.subTest(group=group, device=device), self.assertRaises(ValueError):
                runtime.verify_signed(self.signed, group, device)

    def test_verify_rejects_expired_future_missing_dates_and_devices(self):
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        for dates in ({'ExpirationDate': now - timedelta(seconds=1)},
                      {'CreationDate': now + timedelta(days=1)}, {'CreationDate': 'bad'},
                      {'ExpirationDate': 'bad'}):
            make_ipa(self.signed, dates=dates)
            with self.subTest(dates=dates), self.assertRaises(ValueError):
                runtime.verify_signed(self.signed, GROUP, 'watch-123')
        make_ipa(self.signed, devices=[])
        with self.assertRaises(ValueError): runtime.verify_signed(self.signed, GROUP, 'watch-123')

    def test_verify_requires_matching_application_identifier_with_team(self):
        for application_id in ('', 'org.example.watch', '.org.example.watch',
                               'TEAM123.org.example.other', '*.org.example.watch',
                               'TEAM123.org.example.watch.extra'):
            make_ipa(self.signed, application_id=application_id)
            with self.subTest(application_id=application_id), self.assertRaises(ValueError):
                runtime.verify_signed(self.signed, GROUP, 'watch-123')

    def test_verify_requires_nonempty_profile_uuid(self):
        for profile_uuid in ('', '   ', 123):
            make_ipa(self.signed, profile_uuid=profile_uuid)
            with self.subTest(profile_uuid=profile_uuid), self.assertRaises(ValueError):
                runtime.verify_signed(self.signed, GROUP, 'watch-123')

    def test_verify_requires_group_in_signed_watch_executable(self):
        make_ipa(self.signed, marker=OTHER.encode())
        with self.assertRaises(ValueError): runtime.verify_signed(self.signed, GROUP, 'watch-123')

    def test_import_obsolete_or_corrupt_grouped_does_not_block_upgrade(self):
        grouped = self.root / 'hermes-grouped.ipa'
        make_ipa(grouped, marker=OTHER.encode())
        self.assertEqual(runtime.config_import(self.root)['values']['GROUPED_IPA'], '')
        grouped.write_bytes(b'old-corrupt-file')
        self.assertEqual(runtime.config_import(self.root)['values']['GROUPED_IPA'], '')

    def test_verify_grouped_and_info(self):
        self.assertEqual(runtime.verify_grouped(self.signed, GROUP)['group'], GROUP)
        self.assertEqual(runtime.info(self.signed), {'bundle_id': 'org.example.watch', 'version': '1.2', 'build': '34'})
        with self.assertRaises(ValueError): runtime.verify_grouped(self.signed, OTHER)

    def test_new_ipa_operations_reject_zip_traversal(self):
        make_ipa(self.signed, extra=('../escape', b'bad'))
        for operation, args in ((runtime.info, ()), (runtime.verify_grouped, (GROUP,)),
                                (runtime.verify_signed, (GROUP, 'watch-123'))):
            with self.subTest(operation=operation), self.assertRaises(ValueError):
                operation(self.signed, *args)

    def test_profile_entitlements_not_raw_group_substrings(self):
        make_ipa(self.signed, groups=[], extra=('unrelated.txt', GROUP.encode()))
        with self.assertRaises(ValueError): runtime.config_import(self.root)
        with self.assertRaises(ValueError): runtime.verify_signed(self.signed, GROUP, 'watch-123')

    def test_profile_xml_and_watch_layout_required(self):
        for remove in ('Info.plist', 'WatchExe', 'embedded.mobileprovision'):
            make_ipa(self.signed)
            with zipfile.ZipFile(self.signed) as archive:
                entries = [(item, archive.read(item)) for item in archive.namelist() if item != ROOT + '/' + remove]
            with zipfile.ZipFile(self.signed, 'w') as archive:
                for name, data in entries:
                    archive.writestr(name, data)
            with self.subTest(remove=remove), self.assertRaises((ValueError, KeyError)):
                runtime.verify_signed(self.signed, GROUP, 'watch-123')
        make_ipa(self.signed, profile=False, extra=(ROOT + '/embedded.mobileprovision', b'CMS-without-XML'))
        with self.assertRaises(ValueError): runtime.verify_signed(self.signed, GROUP, 'watch-123')

    def test_cli_dispatch_and_json(self):
        self.conf.write_text('GROUP_ID=' + GROUP + '\n', encoding='utf-8')
        commands = [('config-read', str(self.conf)), ('verify-signed', str(self.signed), GROUP, 'watch-123'),
                    ('verify-grouped', str(self.signed), GROUP), ('info', str(self.signed))]
        self.conf.unlink()
        commands.insert(0, ('config-import', str(self.root)))
        for command in commands:
            if command[0] == 'config-read': self.conf.write_text('GROUP_ID=' + GROUP + '\n', encoding='utf-8')
            output = io.StringIO()
            with self.subTest(command=command), patch.object(sys, 'argv', ['runtime'] + list(command)), contextlib.redirect_stdout(output):
                self.assertEqual(runtime.main(), 0)
            self.assertIsInstance(json.loads(output.getvalue()), dict)

    def test_cli_error_status(self):
        with patch.object(sys, 'argv', ['runtime', 'verify-signed', str(self.signed), GROUP, 'wrong']), contextlib.redirect_stderr(io.StringIO()) as output:
            self.assertEqual(runtime.main(), 1)
        self.assertIn('Watch UDID', output.getvalue())


if __name__ == '__main__':
    unittest.main(verbosity=2)
