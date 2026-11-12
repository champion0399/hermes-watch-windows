"""Management flow regression in temporary HOME; no real signing or devices."""
import datetime as dt
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
import zipfile

REPO=Path(__file__).resolve().parents[1]
GROUP='group.0123456789abcdef'
WATCH='MOCK-WATCH'
ROOT='Payload/HermesCompanion.app/Watch/HermesEnabler2.app'
BUNDLE='XTL-TEAM.com.example.HermesEnabler.watchkitapp'


def make_ipa(path, marker=GROUP, days=1, payload=b'CURRENT', profile=True):
    now=dt.datetime.now(dt.timezone.utc).replace(tzinfo=None)
    info={'WKApplication':True,'CFBundleSupportedPlatforms':['WatchOS'],'CFBundleExecutable':'HermesEnabler2','CFBundleIdentifier':BUNDLE,'CFBundleShortVersionString':'1.0','CFBundleVersion':'1'}
    with zipfile.ZipFile(path,'w') as z:
        z.writestr(ROOT+'/Info.plist',plistlib.dumps(info))
        z.writestr(ROOT+'/HermesEnabler2',payload+marker.encode())
        z.writestr('Payload/HermesCompanion.app/Info.plist',plistlib.dumps({}))
        if profile:
            p={'UUID':'TEST-PROFILE','CreationDate':now-dt.timedelta(minutes=2),'ExpirationDate':now+dt.timedelta(days=days),'ProvisionedDevices':[WATCH], 'Entitlements':{'application-identifier':'TEAM.'+BUNDLE,'com.apple.security.application-groups':[GROUP]}}
            z.writestr(ROOT+'/embedded.mobileprovision',plistlib.dumps(p))


XTOOL=r'''#!/usr/bin/python3
import datetime as dt,json,os,pathlib,plistlib,sys,zipfile
args=sys.argv[1:]; fail=os.environ.get('MOCK_FAIL',''); home=pathlib.Path.home()
with open(os.environ['MOCK_LOG'],'a') as f: f.write('xtool '+json.dumps(args)+'\n')
if args==['install','--help']:
 print('--watch-udid --signed-ipa-output' if fail!='old-xtool' else '--udid'); sys.exit(0)
if args==['auth','status']:
 print('Logged out.' if fail=='auth' else 'Logged in.'); sys.exit(0)
if args[0]=='install':
 if fail=='sign': sys.exit(43)
 if fail=='missing-signed': sys.exit(0)
 output=args[args.index('--signed-ipa-output')+1]
 now=dt.datetime.now(dt.timezone.utc).replace(tzinfo=None)
 with zipfile.ZipFile(args[1]) as src,zipfile.ZipFile(output,'w') as dest:
  for i in src.infolist():
   data=src.read(i.filename)
   if i.filename.endswith('embedded.mobileprovision'): continue
   dest.writestr(i,data)
  info=plistlib.loads(src.read('Payload/HermesCompanion.app/Watch/HermesEnabler2.app/Info.plist'))
  exp=now+dt.timedelta(days=7)
  old=home/'xtool-tmp/hermes-signed.ipa'
  if fail=='expiry-unchanged':
   with zipfile.ZipFile(old) as z: exp=plistlib.loads(z.read('Payload/HermesCompanion.app/Watch/HermesEnabler2.app/embedded.mobileprovision'))['ExpirationDate']
  profile={'UUID':'NEW-PROFILE','CreationDate':now-dt.timedelta(seconds=2),'ExpirationDate':exp,'ProvisionedDevices':['WRONG-WATCH' if fail=='profile-watch' else 'MOCK-WATCH'],'Entitlements':{'application-identifier':'TEAM.'+info['CFBundleIdentifier'],'com.apple.security.application-groups':['group.wrong00000000000' if fail=='profile-group' else os.environ['XTOOL_APP_GROUP_ID']]}}
  if fail=='profile-expired': profile['ExpirationDate']=now-dt.timedelta(days=1)
  dest.writestr('Payload/HermesCompanion.app/Watch/HermesEnabler2.app/embedded.mobileprovision',plistlib.dumps(profile))
 print('Successfully installed!'); sys.exit(0)
sys.exit(99)
'''
VENV=r'''#!/usr/bin/python3
import os,sys
if sys.argv[1:]==['-c','import pymobiledevice3']: sys.exit(0)
os.execv('/usr/bin/python3',['python3']+sys.argv[1:])
'''
HELPER=r'''import json,os,pathlib,plistlib,sys
args=sys.argv[1:]; fail=os.environ.get('MOCK_FAIL','')
with open(os.environ['MOCK_LOG'],'a') as f: f.write('helper '+json.dumps(args)+'\n')
def put(flag,data): pathlib.Path(args[args.index(flag)+1]).open('x').write(json.dumps(data))
if '--device-info' in args:
 if fail=='connect': print('MOCK detailed pairing failure'); raise SystemExit(41)
 put('--device-info',{'udid':'OTHER-WATCH' if fail=='wrong-watch' else 'MOCK-WATCH'})
if '--install' in args:
 if fail=='push': raise SystemExit(44)
 app=pathlib.Path(args[args.index('--install')+1]); assert app.name=='HermesEnabler2.app'
 info=plistlib.loads((app/'Info.plist').read_bytes())
 if fail!='receipt-missing': put('--receipt',{'installed_verified':True,'found':True,'udid':'MOCK-WATCH','bundle_id':info['CFBundleIdentifier'],'version':'WRONG' if fail=='receipt-wrong' else info['CFBundleShortVersionString'],'build':info['CFBundleVersion'],'path':'/mock/watch/HermesEnabler2.app'})
if '--inspect-bundle' in args:
 put('--inspect-output',{'found':fail!='app-missing','udid':'MOCK-WATCH','bundle_id':args[args.index('--inspect-bundle')+1],'version':'1.0','build':'1','path':'/mock/watch/HermesEnabler2.app','installed_verified':False})
'''
RUNTIME=r'''import json,os,runpy,shutil,sys
if sys.argv[1]=='latest':
 if os.environ.get('MOCK_FAIL')=='download': print('MOCK HTTP failure',file=sys.stderr); raise SystemExit(42)
 shutil.copy2(os.environ['MOCK_LATEST_IPA'],sys.argv[2])
 print(json.dumps({'tag':'1.5.1','url':'https://github.com/pookjw/HermesEnabler/releases/download/1.5.1/HermesEnabler.ipa','sha256':'fixture'}))
else: runpy.run_path(os.environ['REAL_RUNTIME'],run_name='__main__')
'''


def exe(path,text):
    path.parent.mkdir(parents=True,exist_ok=True); path.write_text(text); path.chmod(0o755)


class ManagementFlowTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='hermes management '); self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name); self.home=self.root/'home with spaces'; self.home.mkdir()
        self.work=self.home/'xtool-tmp'; self.work.mkdir()
        self.bundle=self.root/'bundle'; self.bundle.mkdir()
        shutil.copy2(REPO/'manage.sh',self.bundle/'manage.sh')
        (self.bundle/'lib').mkdir(); (self.bundle/'lib/hermes_runtime.py').write_text(RUNTIME)
        helpers=self.bundle/'watch-device-helper'; helpers.mkdir()
        (helpers/'watch_device.py').write_text(HELPER); (helpers/'watch_connection.py').write_text('# mock')
        self.signed=self.work/'hermes-signed.ipa'; make_ipa(self.signed)
        self.grouped=self.work/'hermes-grouped.ipa'; make_ipa(self.grouped)
        self.latest=self.root/'latest.ipa'; make_ipa(self.latest,marker='group.com.kamui.escape',payload=b'LATEST',profile=False)
        self.conf=self.work/'hermes-watch.conf'; self.write_conf()
        xtool=self.home/'Developer/xtool-watch-fix/.build/x86_64-unknown-linux-gnu/debug/xtool'; exe(xtool,XTOOL)
        exe(self.home/'Developer/xtool-watch-device-venv/bin/python',VENV)
        bin_path=self.root/'bin'; bin_path.mkdir()
        exe(bin_path/'ip',"#!/bin/bash\nprintf 'default via 127.0.0.1 dev eth0\\n'\n")
        exe(bin_path/'timeout',"#!/bin/bash\n[ \"${MOCK_FAIL:-}\" != bridge ]\n")
        self.env=os.environ.copy(); self.env.update(HOME=str(self.home),PATH=str(bin_path)+':'+self.env['PATH'],MOCK_LOG=str(self.root/'commands.log'),MOCK_LATEST_IPA=str(self.latest),REAL_RUNTIME=str(REPO/'lib/hermes_runtime.py'))
        self.env.pop('XTOOL_BIN',None)

    def write_conf(self,**changes):
        values={'GROUP_ID':GROUP,'WATCH_UDID':WATCH,'APP_NAME':'HermesEnabler2.app','LAST_IPA_URL':'(manual)','SIGNED_IPA':str(self.signed),'GROUPED_IPA':str(self.grouped)}; values.update(changes)
        import shlex
        self.conf.write_text(''.join(k+'='+shlex.quote(v)+'\n' for k,v in values.items()))

    def run_action(self,action='renew',fail=''):
        self.env['MOCK_FAIL']=fail
        return subprocess.run(['bash',str(self.bundle/'manage.sh'),action],env=self.env,stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=30)

    def test_renew_success_has_validated_receipt_and_actual_expiry(self):
        old=hashlib.sha256(self.signed.read_bytes()).digest()
        r=self.run_action(); self.assertEqual(r.returncode,0,r.stdout)
        self.assertIn('续签并验证完成',r.stdout); self.assertNotIn('2027',r.stdout)
        self.assertNotEqual(old,hashlib.sha256(self.signed.read_bytes()).digest())
        self.assertTrue(json.loads((self.work/'last-install-receipt.json').read_text())['installed_verified'])

    def test_upgrade_success_records_upstream_tag_only_after_push(self):
        r=self.run_action('upgrade'); self.assertEqual(r.returncode,0,r.stdout)
        self.assertIn('上游版本: 1.5.1',r.stdout)
        self.assertIn('UPSTREAM_TAG=1.5.1',self.conf.read_text())
        with zipfile.ZipFile(self.signed) as z: self.assertTrue(z.read(ROOT+'/HermesEnabler2').startswith(b'LATEST'))

    def test_upgrade_does_not_require_historical_grouped_ipa(self):
        self.grouped.unlink(); r=self.run_action('upgrade'); self.assertEqual(r.returncode,0,r.stdout)

    def test_renew_preserves_signed_version_instead_of_historical_grouped(self):
        make_ipa(self.grouped,payload=b'HISTORICAL')
        r=self.run_action(); self.assertEqual(r.returncode,0,r.stdout)
        with zipfile.ZipFile(self.signed) as z: self.assertTrue(z.read(ROOT+'/HermesEnabler2').startswith(b'CURRENT'))

    def test_stale_configuration_prefers_new_canonical_signed_cache(self):
        historical=self.work/'hermes-orig-signed.ipa'; make_ipa(historical,payload=b'HISTORICAL')
        os.utime(historical,(1,1)); self.write_conf(SIGNED_IPA=str(historical))
        r=self.run_action(); self.assertEqual(r.returncode,0,r.stdout)
        with zipfile.ZipFile(self.signed) as z: self.assertTrue(z.read(ROOT+'/HermesEnabler2').startswith(b'CURRENT'))

    def test_missing_config_imports_without_deleting_pairing_state(self):
        self.conf.unlink(); state=self.work/'watch-device-state/watch-pairing'; state.mkdir(parents=True); (state/'keep').write_text('pairing')
        r=self.run_action(); self.assertEqual(r.returncode,0,r.stdout)
        self.assertTrue(self.conf.exists()); self.assertEqual((state/'keep').read_text(),'pairing')

    def assert_failure_preserves_cache(self,fail,action='renew'):
        signed=self.signed.read_bytes(); config=self.conf.read_bytes()
        r=self.run_action(action,fail)
        self.assertNotEqual(r.returncode,0,r.stdout)
        self.assertNotIn('并验证完成',r.stdout)
        self.assertEqual(self.signed.read_bytes(),signed)
        self.assertEqual(self.conf.read_bytes(),config)
        self.assertFalse((self.work/'last-install-receipt.json').exists())
        return r

    def test_invalid_auth_session_does_not_claim_permanent_login(self): self.assert_failure_preserves_cache('auth')
    def test_network_failure_stops(self): self.assert_failure_preserves_cache('bridge')
    def test_connect_failure_keeps_real_error(self):
        r=self.assert_failure_preserves_cache('connect'); self.assertIn('MOCK detailed pairing failure',r.stdout)
    def test_different_watch_stops(self): self.assert_failure_preserves_cache('wrong-watch')
    def test_old_xtool_stops(self): self.assert_failure_preserves_cache('old-xtool')
    def test_download_failure_preserves_cache(self): self.assert_failure_preserves_cache('download','upgrade')
    def test_signing_failure_preserves_cache(self): self.assert_failure_preserves_cache('sign')
    def test_missing_signed_output_stops(self): self.assert_failure_preserves_cache('missing-signed')
    def test_wrong_profile_group_stops(self): self.assert_failure_preserves_cache('profile-group')
    def test_wrong_profile_watch_stops(self): self.assert_failure_preserves_cache('profile-watch')
    def test_expired_profile_stops(self): self.assert_failure_preserves_cache('profile-expired')
    def test_unchanged_expiry_is_not_successful_renewal(self): self.assert_failure_preserves_cache('expiry-unchanged')
    def test_watch_push_failure_preserves_cache(self): self.assert_failure_preserves_cache('push')
    def test_missing_receipt_stops(self): self.assert_failure_preserves_cache('receipt-missing')
    def test_mismatched_receipt_stops(self): self.assert_failure_preserves_cache('receipt-wrong')

    def test_status_is_read_only_and_distinguishes_release_from_bundle_version(self):
        before=self.conf.read_bytes(); r=self.run_action('status'); self.assertEqual(r.returncode,0,r.stdout)
        self.assertIn('设备上报版本: 1.0',r.stdout); self.assertEqual(before,self.conf.read_bytes())
        log=(self.root/'commands.log').read_text(); self.assertNotIn('"--signed-ipa-output",',log)
    def test_status_missing_app_is_reported(self): self.assert_failure_preserves_cache('app-missing','status')

    def test_malicious_config_is_not_executed(self):
        sentinel=self.root/'executed'; self.conf.write_text('GROUP_ID=$(touch '+str(sentinel)+')\n')
        r=self.run_action(); self.assertNotEqual(r.returncode,0); self.assertFalse(sentinel.exists())
    def test_concurrent_operation_is_blocked(self):
        with (self.work/'.hermes-operation.lock').open('w') as lock:
            fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            r=self.run_action(); self.assertNotEqual(r.returncode,0); self.assertIn('任务正在运行',r.stdout)


if __name__=='__main__': unittest.main(verbosity=2)
