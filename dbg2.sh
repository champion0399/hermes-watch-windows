#!/bin/bash
WORK=$HOME/xtool-tmp
SIGNED_IPA=$(ls -t $WORK/*-signed.ipa | head -1)
echo "SIGNED_IPA=$SIGNED_IPA"
python3 - "$SIGNED_IPA" <<'PYEOF'
import zipfile, re, sys
z = zipfile.ZipFile(sys.argv[1])
for n in z.namelist():
    if n.endswith('mobileprovision'):
        m = re.search(rb'group\.[a-zA-Z0-9.-]{1,18}', z.read(n))
        if m:
            print('GROUP_ID', m.group().decode())
            sys.exit(0)
print('NO_GROUP')
PYEOF
