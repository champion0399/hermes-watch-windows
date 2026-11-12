"""First-install orchestration tests in disposable HOME, with all mutating tools mocked.
Run inside Ubuntu 24.04 WSL. Does not install packages, sign, or contact devices.
"""
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import pty
import select
import shlex
import shutil
import signal
import tempfile
import time
import unittest
import zipfile

REPO = Path(__file__).resolve().parents[1]

TOOL = r'''#!/usr/bin/python3
import json,os,pathlib,shutil,sys
p=pathlib.Path
name=p(sys.argv[0]).name; a=sys.argv[1:]; stage=os.environ.get('MOCK_FAIL','')
with open(os.environ['MOCK_LOG'],'a') as f: f.write(name+' '+json.dumps(a)+'\n')
base=p(os.environ['HOME']); prefix=base/'Developer/xtool-native-deps/prefix'
if name=='sudo':
 if stage=='apt': sys.exit(31)
 if a and a[0]=='tar': (base/'swift-ready').touch()
 sys.exit(0)
if name=='curl':
 if stage=='swift-download': sys.exit(22)
 dest=p(a[a.index('--output')+1]); asset=a[-1].rsplit('/',1)[-1]
 bundle=p(os.environ['MOCK_BUNDLE'])
 candidate=(bundle/'patches'/asset if asset.endswith('.patch') else bundle/'lib'/asset if asset=='hermes_runtime.py' else bundle/'watch-device-helper'/asset)
 if candidate.is_file(): shutil.copy2(candidate,dest)
 else: dest.write_bytes(b'fixture-download')
 sys.exit(0)
if name=='gpg':
 if stage=='bad-signature' and '--verify' in a: sys.exit(41)
 sys.exit(0)
if name=='tar': sys.exit(0)
if name=='ip':
 if stage!='gateway-empty': print('default via 127.0.0.1 dev eth0')
 sys.exit(0)
if name=='timeout':
 if stage=='bridge': sys.exit(1)
 if stage=='mirrored' and '/dev/tcp/$1/27015' in ' '.join(a): sys.exit(1)
 sys.exit(0)
if name=='git':
 if a[0]=='clone':
  d=p(a[-1]); d.mkdir(parents=True,exist_ok=True); (d/'.git').mkdir()
  (d/'autogen.sh').write_text('#!/bin/bash\nexit 0\n'); (d/'autogen.sh').chmod(0o755)
 elif a[0]=='describe': print('1.24.0')
 elif a[0]=='apply':
  if '--reverse' in a: sys.exit(1)
  if stage=='patch': sys.exit(32)
 sys.exit(0)
if name=='make':
 if a==['install'] and p.cwd().name=='libimobiledevice':
  prefix.joinpath('bin').mkdir(parents=True,exist_ok=True)
  for f in ['idevice_id','ideviceinfo']: shutil.copy2(__file__,prefix/'bin'/f)
 sys.exit(0)
if name=='idevice_id':
 if stage!='phone': print('MOCK-PHONE')
 sys.exit(0)
if name=='ideviceinfo': print('false'); sys.exit(0)
if name=='swift':
 if '--version' in a:
  if stage in ['fresh-swift','bad-signature','swift-download'] and not (base/'swift-ready').exists(): sys.exit(1)
  print('Swift version 6.4.1'); sys.exit(0)
 if stage=='build': sys.exit(33)
 dest=base/'Developer/xtool-watch-src/.build/debug/xtool'; dest.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(__file__,dest); sys.exit(0)
if name=='xtool':
 if a[:2]==['auth','status']: print('Logged in.'); sys.exit(0)
 if a[0]=='install':
  if stage=='sign': sys.exit(34)
  if stage!='signed-missing': shutil.copy2(a[1],a[a.index('--signed-ipa-output')+1])
  print('Successfully installed!'); sys.exit(0)
if name=='pip': sys.exit(0)
print('Unhandled mock '+name+' '+str(a),file=sys.stderr); sys.exit(90)
'''
VENV = r'''#!/usr/bin/python3
import os,sys,pathlib,subprocess
args=sys.argv[1:]
if args[:2]==['-m','pip']: sys.exit(0)
if args[:2]==['-m','pymobiledevice3']:
 assert args[2:5]==['amfi','reveal-developer-mode','--udid']
 if os.environ.get('MOCK_FAIL')=='phone-developer': sys.exit(42)
 sys.exit(0)
os.execv('/usr/bin/python3',['python3']+args)
'''
HELPER = r'''import json,sys,pathlib,os
if '--device-info' in sys.argv:
 p=pathlib.Path(sys.argv[sys.argv.index('--device-info')+1]); p.write_text(json.dumps({'udid':'MOCK-WATCH'}))
if '--install' in sys.argv:
 p=pathlib.Path(sys.argv[sys.argv.index('--install')+1]); assert p.name=='HermesEnabler2.app'; assert (p/'Info.plist').exists()
 if os.environ.get('MOCK_FAIL')=='push': raise SystemExit(35)
 print('Installed and verified in the Watch app registry.')
'''


def executable(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text); path.chmod(0o755)


def fixture(path, missing_marker=False):
    root='Payload/HermesCompanion.app/Watch/HermesEnabler2.app'
    info={'WKApplication':True,'CFBundleSupportedPlatforms':['WatchOS'],'CFBundleExecutable':'HermesEnabler2'}
    with zipfile.ZipFile(path,'w') as z:
        z.writestr(root+'/Info.plist',plistlib.dumps(info))
        z.writestr(root+'/HermesEnabler2',b'new-upstream' if missing_marker else b'MACHOgroup.com.kamui.escape')
        z.writestr('Payload/HermesCompanion.app/Info.plist',plistlib.dumps({}))


class FirstInstallFlowTests(unittest.TestCase):
    def run_install(self, fail='', confirm='y', piped=False):
        with tempfile.TemporaryDirectory(prefix='hermes-first-install-') as directory:
            base=Path(directory); home=base/'home'; home.mkdir(); bundle=base/'bundle'; bundle.mkdir()
            shutil.copy2(REPO/'install.sh',bundle/'install.sh')
            shutil.copytree(REPO/'patches',bundle/'patches')
            helpers=bundle/'watch-device-helper'; helpers.mkdir()
            (helpers/'watch_device.py').write_text(HELPER); (helpers/'watch_connection.py').write_text('# mock helper')
            lib=bundle/'lib'; lib.mkdir()
            fixture_path=base/'upstream.ipa'; fixture(fixture_path,fail=='marker')
            runtime=lib/'hermes_runtime.py'
            runtime.write_text('''import sys,os,shutil,json,runpy
if len(sys.argv)>1 and sys.argv[1]=='latest':
 shutil.copy2(os.environ['MOCK_IPA'],sys.argv[2])
 print(json.dumps({'tag':'TEST','url':'https://github.com/pookjw/HermesEnabler/releases/download/TEST/HermesEnabler.ipa','sha256':'fixture'}))
else:
 runpy.run_path(os.environ['REAL_RUNTIME'],run_name='__main__')
''')
            prefix=home/'Developer/xtool-native-deps/prefix/bin'; prefix.mkdir(parents=True)
            for name in ['sudo','ip','timeout','git','make','swift','curl','gpg','tar']:
                executable(prefix/name,TOOL)
            executable(home/'Developer/xtool-watch-venv/bin/python',VENV)
            env=os.environ.copy(); env.update(HOME=str(home),USER='user',PATH=str(prefix)+':'+env['PATH'],MOCK_LOG=str(base/'commands.log'),MOCK_FAIL=fail,MOCK_IPA=str(fixture_path),MOCK_BUNDLE=str(bundle),REAL_RUNTIME=str(REPO/'lib/hermes_runtime.py'))
            env.pop('XTOOL_APP_GROUP_ID',None)
            pid,fd=pty.fork()
            if pid==0:
                command=['bash','-c','cat '+shlex.quote(str(bundle/'install.sh'))+' | bash'] if piped else ['bash',str(bundle/'install.sh')]
                os.execve('/bin/bash',command,env)
            output=b''; deadline=time.monotonic()+25; answered=set(); status=None
            try:
                while time.monotonic()<deadline:
                    ready,_,_=select.select([fd],[],[],0.1)
                    if ready:
                        try: chunk=os.read(fd,65536)
                        except OSError: chunk=b''
                        output+=chunk
                    text=output.decode(errors='replace')
                    if '(y/N)' in text and 'confirm' not in answered:
                        os.write(fd,(confirm+'\n').encode()); answered.add('confirm')
                    if '输入 App Group ID' in text and 'group' not in answered:
                        os.write(fd,b'\n'); answered.add('group')
                    got,status=os.waitpid(pid,os.WNOHANG)
                    if got: break
                else:
                    os.kill(pid,signal.SIGKILL); os.waitpid(pid,0)
                    self.fail('Installer timed out: '+output.decode(errors='replace'))
            finally: os.close(fd)
            code=os.waitstatus_to_exitcode(status)
            text=output.decode(errors='replace')
            conf=home/'xtool-tmp/hermes-watch.conf'
            conf_text=conf.read_text() if conf.exists() else ''
            log=(base/'commands.log').read_text() if (base/'commands.log').exists() else ''
            return code,text,conf_text,log

    def test_clean_install_full_orchestration(self):
        code,text,conf,log=self.run_install()
        self.assertEqual(code,0,text)
        self.assertIn('全部完成',text)
        self.assertIn('HermesEnabler2.app',conf)
        self.assertIn('UPSTREAM_TAG=TEST',conf)
        self.assertRegex(conf,r'LAST_SUCCESS_AT=\d{4}-\d{2}-\d{2}T')
        self.assertRegex(conf,r'GROUP_ID=group\.[a-f0-9]{16}')
        self.assertIn('Installed and verified',text)
        self.assertIn('libimobiledevice-glue',log)

    def assert_failure(self, stage):
        code,text,conf,log=self.run_install(stage)
        self.assertNotEqual(code,0,text)
        self.assertNotIn('全部完成',text)
        self.assertEqual(conf,'')
        return text,log

    def test_mirrored_network_falls_back_to_localhost(self):
        code,text,conf,log=self.run_install('mirrored')
        self.assertEqual(code,0,text)
        self.assertIn('usbmuxd reachable: 127.0.0.1:27015',text)

    def test_no_gateway_still_uses_reachable_localhost(self):
        code,text,conf,log=self.run_install('gateway-empty')
        self.assertEqual(code,0,text)
        self.assertIn('usbmuxd reachable: 127.0.0.1:27015',text)

    def test_no_usbmux_bridge_stops_before_package_install(self):
        text,log=self.assert_failure('bridge')
        self.assertNotIn('sudo',log)

    def test_piped_script_keeps_interactive_terminal_input(self):
        code,text,conf,log=self.run_install(piped=True)
        self.assertEqual(code,0,text)
        self.assertIn('全部完成',text)
        self.assertIn('HermesEnabler2.app',conf)

    def test_fresh_swift_download_and_verify_orchestration(self):
        code,text,conf,log=self.run_install('fresh-swift')
        self.assertEqual(code,0,text)
        self.assertIn('--verify',log)
        self.assertIn('全部完成',text)

    def test_bad_swift_signature_stops(self): self.assert_failure('bad-signature')
    def test_swift_download_http_failure_stops(self): self.assert_failure('swift-download')
    def test_apt_failure_stops(self): self.assert_failure('apt')
    def test_no_phone_stops(self): self.assert_failure('phone')
    def test_phone_developer_mode_command_failure_stops(self): self.assert_failure('phone-developer')
    def test_patch_failure_stops(self): self.assert_failure('patch')
    def test_build_failure_stops(self): self.assert_failure('build')
    def test_upstream_marker_changed_stops_before_signing(self):
        text,log=self.assert_failure('marker')
        self.assertNotIn('xtool ["install"',log)
    def test_signing_failure_stops(self): self.assert_failure('sign')
    def test_signer_missing_output_stops(self): self.assert_failure('signed-missing')
    def test_watch_push_failure_does_not_report_success(self): self.assert_failure('push')
    def test_developer_mode_not_confirmed_stops(self):
        code,text,conf,log=self.run_install(confirm='n')
        self.assertNotEqual(code,0); self.assertNotIn('全部完成',text)
        self.assertNotIn('xtool ["install"',log)


if __name__=='__main__': unittest.main(verbosity=2)
