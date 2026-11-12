from pathlib import Path
import unittest

PATCH=Path(__file__).resolve().parents[1]/'patches/xtool-watch-1.24.0.patch'
class PatchContentsTests(unittest.TestCase):
    def test_utf8_lf_patch(self):
        data=PATCH.read_bytes()
        self.assertFalse(data.startswith((b'\xff\xfe',b'\xef\xbb\xbf')))
        data.decode('utf-8')
        self.assertNotIn(b'\r',data)
    def test_required_new_signer_sources_included(self):
        data=PATCH.read_text(encoding='utf-8')
        for name in ['Sources/XKit/Signer/ProvisioningBundle.swift','Sources/XKit/Signer/SignedIPAOutput.swift','Vendor/zsign/Package.swift','Vendor/zsign/LICENSE','Vendor/zsign/src/lib/Zupersign.cpp']:
            self.assertIn('+++ b/'+name,data)
    def test_app_group_configured_at_runtime(self):
        self.assertIn('ProcessInfo.processInfo.environment["XTOOL_APP_GROUP_ID"]',PATCH.read_text(encoding='utf-8'))

if __name__=='__main__': unittest.main(verbosity=2)
