"""Read existing configuration and cached signed IPA; no device writes or login."""
import importlib.util
import json
from pathlib import Path
spec=importlib.util.spec_from_file_location('runtime',Path(__file__).resolve().parents[1]/'lib/hermes_runtime.py')
runtime=importlib.util.module_from_spec(spec); spec.loader.exec_module(runtime)
work=Path.home()/'xtool-tmp'
values=runtime.config_read(work/'hermes-watch.conf')['values']
source=work/'hermes-signed.ipa'
if not source.is_file(): source=Path(values['SIGNED_IPA'])
result=runtime.verify_signed(source,values['GROUP_ID'],values['WATCH_UDID'])
print('Existing configuration and cached Watch profile: PASS')
print(json.dumps({k:result[k] for k in ['created','expires','remaining_hours','validation','cms_signature_verified']},ensure_ascii=False))
