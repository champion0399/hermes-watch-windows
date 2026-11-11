import ctypes as c
import os
from pathlib import Path
import plistlib

os.environ['USBMUXD_SOCKET_ADDRESS'] = '172.27.128.1:27015'
mobile = c.CDLL('libimobiledevice-1.0.so.6')
plist = c.CDLL('libplist-2.0.so.4')
pointer = c.c_void_p
mobile.idevice_new.argtypes = [c.POINTER(pointer), c.c_char_p]
mobile.companion_proxy_client_start_service.argtypes = [pointer, c.POINTER(pointer), c.c_char_p]
mobile.companion_proxy_get_device_registry.argtypes = [pointer, c.POINTER(pointer)]
mobile.companion_proxy_client_free.argtypes = [pointer]
mobile.idevice_free.argtypes = [pointer]
plist.plist_to_xml.argtypes = [pointer, c.POINTER(pointer), c.POINTER(c.c_uint32)]
plist.plist_free.argtypes = [pointer]
libc = c.CDLL(None)
libc.free.argtypes = [pointer]
device, client, registry, xml = pointer(), pointer(), pointer(), pointer()
try:
    for label, result in [
        ('Connect iPhone', mobile.idevice_new(c.byref(device), None)),
    ]:
        if result:
            raise RuntimeError(f'{label}: error {result}')
    result = mobile.companion_proxy_client_start_service(device, c.byref(client), b'xtool-watch-probe')
    if result:
        raise RuntimeError(f'Companion service: error {result}')
    result = mobile.companion_proxy_get_device_registry(client, c.byref(registry))
    if result:
        raise RuntimeError(f'Paired watch registry: error {result}')
    size = c.c_uint32()
    plist.plist_to_xml(registry, c.byref(xml), c.byref(size))
    data = c.string_at(xml, size.value)
    parsed = plistlib.loads(data)
    path = Path('/home/champ/xtool-tmp/paired-watch.plist')
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, 'wb') as stream:
        stream.write(data)
    print('Paired device registry saved locally.')
    print('Registry type:', type(parsed).__name__)
    if isinstance(parsed, list):
        print('Paired device entries:', len(parsed))
        for item in parsed:
            if isinstance(item, dict):
                print('Available fields:', ', '.join(item.keys()))
finally:
    if xml:
        libc.free(xml)
    if registry:
        plist.plist_free(registry)
    if client:
        mobile.companion_proxy_client_free(client)
    if device:
        mobile.idevice_free(device)
