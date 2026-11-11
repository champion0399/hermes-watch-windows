# Sideload HermesEnabler to Apple Watch — full guide (Windows + WSL + free Apple ID, no Mac)

**[中文](README.md) | English**

> **Note for AI agents**: this is a from-scratch runbook. Do not skip the "verify" steps.
> All placeholders — `champ`, `<DEPS_PREFIX>`, `<WATCH_UDID>`, `<PHONE_UDID>`, `<GROUP_ID>` — must be replaced with real values.
> Verified on: Windows 11 + WSL2 Ubuntu 24.04, Swift 6.4.1, libimobiledevice 1.4.0, iPhone (iOS 26.x), Apple Watch (watchOS 27.2), free Apple ID.

---

## Part 0 · Hardware & account prerequisites

| Item | Requirement | How to check |
|---|---|---|
| Computer | Windows 10/11 with WSL2 support | `wsl --status` |
| iPhone | USB-connected, has tapped "Trust This Computer" | Trust prompt appears on plugin |
| Apple Watch | Paired to the iPhone, worn & unlocked | Watch face reachable |
| Apple account | **Free** Apple ID — no paid developer program | Needed later for `xtool auth` |
| iPhone developer mode | Settings → Privacy & Security → Developer Mode → ON | Toggle at the very bottom; reboot required |
| Watch developer mode | Watch → Settings → Privacy & Security → Developer Mode → ON | **Toggle is hidden by default** — must do the reveal step in 2.6 first |

---

## Part 1 · Windows-side software

### 1.1 Install Apple Devices (or iTunes)

Purpose: provides `AppleMobileDeviceService`, which runs usbmuxd on `127.0.0.1:27015` — the bridge between WSL and the iPhone.

- Install **Apple Devices** from the Microsoft Store (or iTunes).
- Plug in the iPhone, wait for Windows to recognize it, tap **Trust** on the iPhone.
- Verify: `netstat -ano | findstr ":27015"` should show `127.0.0.1:27015 LISTENING` owned by `AppleMobileDeviceService`.

### 1.2 Install WSL2 + Ubuntu 24.04

In an elevated PowerShell:

```powershell
wsl --install -d Ubuntu-24.04
```

Launch once and create the Linux user (this guide uses `champ`).

### 1.3 WSL gateway address (critical)

WSL cannot reach Windows `127.0.0.1` directly; it goes through the gateway. Find it inside WSL:

```bash
ip route show default | awk '{print $3}'     # e.g. 172.27.128.1
```

Throughout this guide `USBMUXD_SOCKET_ADDRESS=172.27.128.1:27015` — replace the IP with your gateway. WSL's relay maps `<gateway-ip>:27015` to `127.0.0.1:27015` on Windows, so WSL processes talk to usbmuxd through it.

---

## Part 2 · WSL environment

### 2.1 Base build tools

```bash
sudo apt update
sudo apt install -y build-essential git curl wget pkg-config autoconf automake libtool \
  libssl-dev libplist-dev unzip zip python3 python3-venv python3-pip
```

### 2.2 Swift 6.4.x toolchain

```bash
cd /tmp
curl -LO https://download.swift.org/swift-6.4.1-release/ubuntu2404/swift-6.4.1-RELEASE/swift-6.4.1-RELEASE-ubuntu24.04.tar.gz
sudo mkdir -p /opt/swift-6.4.1
sudo tar -xzf swift-6.4.1-RELEASE-ubuntu24.04.tar.gz -C /opt/swift-6.4.1 --strip-components=1
echo 'export PATH=/opt/swift-6.4.1/usr/bin:$PATH' >> ~/.bashrc
export PATH=/opt/swift-6.4.1/usr/bin:$PATH
swift --version   # should print Swift version 6.4.1
```

Swift runtime deps:

```bash
sudo apt install -y binutils gnupg2 libc6-dev libcurl4-openssl-dev libedit2 \
  libgcc-13-dev libpython3-dev libstdc++-13-dev libxml2-dev libz3-dev \
  pkg-config tzdata unzip zlib1g-dev libncurses-dev libsqlite3-dev
```

### 2.3 libimobiledevice 1.4 family (from source)

xtool's device layer needs the latest versions (Ubuntu's are too old). Build into a private prefix:

```bash
mkdir -p ~/Developer/xtool-native-deps/{src,prefix}
base=~/Developer/xtool-native-deps
prefix=$base/prefix
export PKG_CONFIG_PATH=$prefix/lib/pkgconfig
export LD_LIBRARY_PATH=$prefix/lib

build_dep() {
  local project=$1 version=$2
  local src=$base/src/$project
  [ -d $src/.git ] || git clone --depth 1 --branch $version https://github.com/libimobiledevice/$project.git $src
  cd $src
  ./autogen.sh --prefix=$prefix --without-cython --without-tools
  make -j4 && make install
}
build_dep libplist 2.6.0
build_dep libimobiledevice-glue 1.3.1
build_dep libusbmuxd 2.1.0
build_dep libtatsu 1.0.4
build_dep libimobiledevice 1.4.0
```

**Note**: `--without-tools` skips the `idevice_*` CLI tools used by the diagnostics below. Rebuild `libimobiledevice` without `--without-tools`, or `apt install libimobiledevice-utils`/`libimobiledevice-tools` just for diagnosis.

Self-check (iPhone unlocked, screen on, USB connected):

```bash
export USBMUXD_SOCKET_ADDRESS=172.27.128.1:27015
idevice_id -l                       # prints <PHONE_UDID>
ideviceinfo -k DeviceName           # prints phone name
ideviceinfo -k PasswordProtected    # must be false
```

**Gotcha**: while the iPhone is locked, `idevice_id` briefly lists then loses the device and everything later reports `No device found`. Keep the phone unlocked for the whole procedure.

### 2.4 xtool source (fork: xtool-watch)

```bash
cd ~/Developer
git clone https://github.com/xtool-org/xtool.git xtool-watch-fix
cd xtool-watch-fix && git checkout 1.24.0
```

Apply the patches in **Part 3**.

### 2.5 pymobiledevice3 (direct Watch install)

```bash
python3 -m venv ~/Developer/xtool-watch-device-venv
~/Developer/xtool-watch-device-venv/bin/pip install pymobiledevice3
```

Put `watch_connection.py` and `watch_device.py` (full source in `watch-device-helper/` of this repo) into one directory.

### 2.6 Reveal the hidden Developer Mode toggle on the Watch (do not skip)

**The Watch's Developer Mode toggle is hidden by default** — like on iOS, a "developer machine" must connect and request a reveal before the switch appears under Watch → Settings → Privacy & Security. On macOS Xcode does this silently; without a Mac, send the reveal request via the watch's amfi lockdown service:

```bash
cd <watch-device-helper dir>
USBMUXD_SOCKET_ADDRESS=172.27.128.1:27015 \
  ~/Developer/xtool-watch-device-venv/bin/python3 \
  watch_device.py --state-directory ~/xtool-tmp/watch-device-state \
  --pair --reveal-developer-mode
```

Flow: the helper reaches the watch via the iPhone's companion_proxy → first run triggers "Trust This Computer" **on the Watch** (wear it, unlock, accept; pairing records are cached in `--state-directory`) → sends `{"action": 0}` to `com.apple.amfi.lockdown` → prints a confirmation.

Then on the Watch itself: **Settings → Privacy & Security → the Developer Mode toggle now appears at the bottom → turn it on → the watch asks to restart → after reboot, confirm the "Developer Mode" prompt on the watch.**

Verify it took effect:

```bash
watch_device.py --state-directory ~/xtool-tmp/watch-device-state
# output should contain "developer_mode": true
```

If `false`, go back to Watch Settings and make sure the switch is on and the restart completed.

---

## Part 3 · xtool patches (3 sites)

### 3.1 Allow App Groups on free teams

`Sources/XKit/DeveloperServices/App IDs/Entitlements/DeveloperServicesCapability.swift`:

```swift
extension AppGroupEntitlement: EntitlementWithCapability {
    var capability: DeveloperServicesCapability {
        DeveloperServicesCapability(.appGroups, isFree: true)   // was false
    }
}
```

### 3.2 Inject an App Group entitlement for the Watch bundle

`Sources/XKit/DeveloperServices/App IDs/DeveloperServicesAddAppOperation.swift` — insert **before** `let appID = try await upsertApp(...)`:

```swift
if isWatch,
   let existing = try? entitlements.entitlements(),
   !existing.contains(where: { $0 is AppGroupEntitlement }) {
    var patched = existing
    patched.append(AppGroupEntitlement(rawValue: [
        .init(rawValue: "<GROUP_ID>")   // e.g. group.com.yourname.hermes; 22 bytes, must match the binary patch
    ]))
    try? entitlements.setEntitlements(patched)
}
```

### 3.3 Keep the group ID verbatim

`Sources/XKit/DeveloperServices/App Groups/DeveloperServicesAssignAppGroupsOperation.swift` — create the group with the ID untouched:

```swift
let request = DeveloperServicesAddAppGroupRequest(
    platform: .iOS,
    teamID: xcodeAuthData.teamID,
    name: ProvisioningIdentifiers.groupName(fromSanitized: sanitized),
    groupID: groupID          // verbatim; do NOT regenerate via ProvisioningIdentifiers.groupID(fromSanitized:)
)
```

### 3.4 Prerequisite: per-embedded-app provisioning

`ProvisioningBundle.discover` must traverse `Watch/*.app` (marked `isWatch = true`), and every bundle must get its own App ID + profile. `DeveloperServicesFetchProfileOperation` must add the **Watch UDID** (not the iPhone UDID) to `ProvisionedDevices` when `isWatch`. If your base lacks per-bundle provisioning, implement it first — it is a hard requirement for the Watch to accept the app.

### 3.5 Build

```bash
export PATH=/opt/swift-6.4.1/usr/bin:$PATH
cd ~/Developer/xtool-watch-fix
prefix=~/Developer/xtool-native-deps/prefix
swift build --build-system native --pkg-config-path $prefix/lib/pkgconfig -j 4 \
  -Xcc -I$prefix/include -Xlinker -L$prefix/lib \
  -Xlinker -rpath -Xlinker $prefix/lib --product xtool
```

**`--build-system native` is required**, otherwise `SwiftyMobileDevice` fails with `cannot find idevice_subscription_context_t`.

Launcher:

```bash
sudo tee /usr/local/bin/xtool-watch <<'EOF'
#!/bin/sh
export LD_LIBRARY_PATH=$HOME/Developer/xtool-native-deps/prefix/lib
export USBMUXD_SOCKET_ADDRESS=172.27.128.1:27015
exec $HOME/Developer/xtool-watch-fix/.build/debug/xtool "$@"
EOF
sudo chmod +x /usr/local/bin/xtool-watch
```

Sign in:

```bash
xtool-watch auth
# enter Apple ID & password, complete Apple 2FA/device-code flow
xtool-watch auth status    # confirm the Team ID resolved
```

---

## Part 4 · Prepare the HermesEnabler IPA

### 4.1 Download

```bash
mkdir -p ~/xtool-tmp && cd ~/xtool-tmp
curl -L -o hermes-1.4.1.ipa https://github.com/nicegram/HermesEnabler/releases/download/1.4.1/HermesEnabler.ipa
# if 404, check the releases page for the actual asset name
```

### 4.2 Rewire the App Group ID (critical)

The binary hardcodes `group.com.kamui.escape` (the original developer's group — nobody else can register it; Apple replies Error 35 "not available"). Replace it with a unique **22-byte** ID from your own account, e.g. `group.com.friend.hermes` (22 chars). Use `patch-hermes-group.py` from this repo:

```bash
python3 patch-hermes-group.py hermes-1.4.1.ipa hermes-1.4.1-grouped.ipa 'group.com.<your-id>'
# expected: replaced 2 (one occurrence per fat-binary slice)
```

**This ID must byte-for-byte match the string in patch 3.2.**

### 4.3 Get the paired Watch UDID

Watch UDID is not shown in the iOS UI. Read the pairing registry via companion_proxy:

```bash
cd <watch-device-helper dir>
USBMUXD_SOCKET_ADDRESS=172.27.128.1:27015 \
  ~/Developer/xtool-watch-device-venv/bin/python3 \
  watch_device.py --state-directory ~/xtool-tmp/watch-device-state \
  --device-info ~/xtool-tmp/watch-info.json
```

The first run triggers a "Trust This Computer" prompt **on the Watch** — accept it while wearing the watch, unlocked. Afterwards `watch-info.json` contains `udid` — that is `<WATCH_UDID>`.

**Gotcha**: the watch pairing cache lives under `--state-directory`; deleting it forces a re-trust.

### 4.4 Sign & install to the iPhone

```bash
xtool-watch install ~/xtool-tmp/hermes-1.4.1-grouped.ipa \
  --watch-udid <WATCH_UDID> \
  --signed-ipa-output ~/xtool-tmp/hermes-signed.ipa
```

Expected: `Provisioning` (Apple creates `<GROUP_ID>` under your free team — yes, free teams can create app groups) → `Signing → Packaging → Installing → Verifying → Successfully installed!`

**Verify two assertions right after install:**

```python
import zipfile, plistlib
z = zipfile.ZipFile('hermes-signed.ipa')
raw = z.read('Payload/HermesCompanion.app/Watch/HermesEnabler2.app/embedded.mobileprovision')
p = plistlib.loads(raw[raw.find(b'<?xml'):raw.find(b'</plist>')+8])
assert '<WATCH_UDID>' in p['ProvisionedDevices']
assert p['Entitlements']['com.apple.security.application-groups'] == ['<GROUP_ID>']
```

### 4.5 Install to the Watch (bypass the iOS Watch app!)

The iOS Watch app's "Available Apps → Install" uses an async sync channel that commonly fails with "Unable to install, try again later". Bypass it — push the signed `.app` straight to the watch's lockdown:

```bash
cd ~/xtool-tmp
unzip -o -q hermes-signed.ipa 'Payload/HermesCompanion.app/Watch/HermesEnabler2.app/*' -d extract
mv 'extract/Payload/HermesCompanion.app/Watch/HermesEnabler2.app' ./HermesEnabler2.app

cd <watch-device-helper dir>
USBMUXD_SOCKET_ADDRESS=172.27.128.1:27015 \
  ~/Developer/xtool-watch-device-venv/bin/python3 \
  watch_device.py --state-directory ~/xtool-tmp/watch-device-state \
  --install ~/xtool-tmp/HermesEnabler2.app
```

`Install: 100%` + `Installed and verified` = done. **Open HermesEnabler directly on the Watch.**

---

## Part 5 · Troubleshooting table

| Symptom | Cause | Fix |
|---|---|---|
| `Error 35 ... group.com.kamui.escape is not available` | Group ID owned by the original dev | 4.2 — use your own ID |
| `idevice_subscription_context_t` compile error | missing `--build-system native` | 3.5 |
| `No device found` / device flickers | iPhone locked | unlock & retry |
| Watch "Unable to install, try again later" | iOS Watch-app sync channel | 4.5 — direct install |
| Watch "cannot verify its integrity" | profile lacks Watch UDID / no per-watch profile | re-check 4.4 assertions |
| No "Developer Mode" toggle in Watch Settings | toggle hidden by default | 2.6 — run `--reveal-developer-mode` first |
| `--install` says "Enable Developer Mode" | not actually enabled/confirmed on the watch | enable in Watch Settings, restart, confirm prompt |
| Watch asks "Trust This Computer" | fresh pairing cache | wear & unlock watch, accept when the helper triggers it |
| Runtime "MobileGestalt Access Failed" with correct group | escape path broken on this watchOS (upstream issue #7) | not a signing issue; wait for upstream fix |
| `swift: command not found` | new shell without PATH | `export PATH=/opt/swift-6.4.1/usr/bin:$PATH` |
| App stops opening after 7 days | free-account profile expiry | rerun 4.4 + 4.5 |

---

## Part 6 · Repo contents

```
README.md                  中文完整版 (default)
README.en.md               this guide (English)
patch-hermes-group.py      App Group ID rewriter (22-byte, same-length replace)
probe-paired-watch.py      ctypes helper: dump paired-watch registry via companion_proxy
watch-device-helper/
  watch_connection.py      CompanionWatchLockdownClient + WatchConnection
  watch_device.py          CLI: query watch info / push a signed .app to the watch
```

---

## One-line summary

Install Apple Devices → set up WSL + Swift + libimobiledevice → clone xtool, apply 3 patches, build → `xtool-watch auth` → patch the group ID in the IPA → `xtool-watch install` to the iPhone → push the `.app` to the watch with `watch_device.py` → open on the watch.
