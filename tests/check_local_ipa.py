"""Read cached upstream IPA; patch and extract only inside a temporary directory."""
import importlib.util
from pathlib import Path
import tempfile
import zipfile
spec=importlib.util.spec_from_file_location('runtime',Path(__file__).resolve().parents[1]/'lib/hermes_runtime.py')
runtime=importlib.util.module_from_spec(spec); spec.loader.exec_module(runtime)
source=Path.home()/'xtool-tmp/hermes-latest.ipa'
with tempfile.TemporaryDirectory(prefix='hermes-ipa-validation-') as directory:
    root=Path(directory)
    result=runtime.patch(source,root/'patched.ipa','group.0123456789abcdef')
    assert result['replacements']>0,result
    app=Path(runtime.extract_watch(root/'patched.ipa',root/'extract'))
    assert app.name=='HermesEnabler2.app',app
    assert (app/'Info.plist').is_file()
    print('Cached real upstream IPA patch/extract: PASS',result)
    print('Selected watch app:',app.name)
