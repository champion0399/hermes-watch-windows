#!/usr/bin/env python3
"""Patch HermesEnabler2 binary's hardcoded App Group id.

Replaces 'group.com.kamui.escape' (22 bytes) with a team-unique id of the
same length. Rewrites the IPA in-place-safe via a new output file.

Usage: patch-hermes-group.py <input.ipa> <output.ipa> <new-group-id>
"""
import sys, zipfile, shutil, os

OLD = b'group.com.kamui.escape'
assert len(OLD) == 22

def main():
    src, dst, new_id = sys.argv[1], sys.argv[2], sys.argv[3]
    new = new_id.encode()
    if len(new) != 22:
        raise SystemExit(f'new group id must be exactly 22 bytes, got {len(new)}')
    if not new.startswith(b'group.'):
        raise SystemExit('new group id must start with group.')

    zin = zipfile.ZipFile(src)
    zout = zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED)
    replaced = 0
    for item in zin.infolist():
        data = zin.read(item.filename)
        if item.filename.endswith('HermesEnabler2') or item.filename.endswith('HermesCompanion'):
            count = data.count(OLD)
            if count:
                data = data.replace(OLD, new)
                replaced += count
                print(f'{item.filename}: replaced {count} occurrence(s)')
        zout.writestr(item, data)
    zout.close()
    print(f'total replaced: {replaced}')
    if replaced == 0:
        raise SystemExit('no occurrences found; check input IPA')
    print(f'wrote {dst}')

if __name__ == '__main__':
    main()
