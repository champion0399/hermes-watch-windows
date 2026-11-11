# HermesEnabler 瑁呭埌 Apple Watch 鍏ㄦ祦绋嬫墜鍐岋紙Windows + WSL + 鍏嶈垂 Apple 璐﹀彿锛岄浂 Mac锛?
**涓枃 | [English](README.en.md)**

> **鑷磋阿**锛氭湰鏁欑▼鍙槸渚ц浇鏂规硶鈥斺€旂湡姝ｇ殑鍔熻嚕鏄?[HermesEnabler](https://github.com/pookjw/HermesEnabler) 鍙婂叾鍘熶綔鑰?**pookjw**锛圝inwoo Kim锛夈€傛病鏈変粬鍋氱殑琛ㄧ洏缁曡繃宸ュ叿锛屽氨娌℃湁杩欎釜鏁欑▼瀛樺湪鐨勬剰涔夈€?>
> **鎵ц宸ュ叿寤鸿**锛氭帹鑽愮敤 **DeepSeek Harness**锛坉sh锛夎窇鏈祦绋嬧€斺€旀暣濂楀伐浣滄祦娑夊強浜岃繘鍒?patch銆丄pple 绛惧悕銆佽澶囩洿杩炵瓑鎿嶄綔锛孋odex 绛夊彈涓ユ牸瀹夊叏鍗忚绾︽潫鐨?agent 浼氬湪涓€旇鎷︽埅鎴栬姹傞€愭瀹℃壒锛屾墦鏂祦绋嬨€侱eepSeek Harness 鎻愪緵 unrestricted sandbox 妯″紡锛岃兘椤虹晠璺戝畬銆?>
> **缁?AI agent 鐨勮鏄?*锛氳繖鏄竴浠戒粠澶村紑濮嬬殑瀹屾暣鎿嶄綔鎵嬪唽锛屼笉瑕佽烦杩囦换浣?鑷"姝ラ銆?> 鎵€鏈夎矾寰勯噷鐨?`champ`銆乣<DEPS_PREFIX>`銆乣<WATCH_UDID>`銆乣<PHONE_UDID>`銆乣<GROUP_ID>` 鏄崰浣嶇锛屾寜瀹為檯鍊兼浛鎹€?> 宸查獙璇佺幆澧冿細Windows 11 + WSL2 Ubuntu 24.04銆丼wift 6.4.1銆乴ibimobiledevice 1.4.0銆乮Phone锛坕OS 27.0.1锛夈€丄pple Watch锛坵atchOS 27.2锛夈€佸厤璐?Apple ID銆?
---

## 绗?0 閮ㄥ垎 路 纭欢涓庤处鍙峰噯澶?
| 椤?| 瑕佹眰 | 妫€鏌ユ柟娉?|
|---|---|---|
| 鐢佃剳 | Windows 10/11锛岃兘鐢?WSL2 | `wsl --status` |
| iPhone | USB 杩炵數鑴戯紝鐐硅繃"淇′换姝ょ數鑴? | 鎻掔嚎鍚?iPhone 寮逛俊浠绘 |
| Apple Watch | 宸蹭笌 iPhone 閰嶅锛屼僵鎴翠笖瑙ｉ攣 | 鎵嬭〃鑳芥甯哥湅琛ㄧ洏 |
| Apple 璐﹀彿 | **鍏嶈垂** Apple ID 鍗冲彲锛屾棤闇€浠樿垂寮€鍙戣€?| 璁颁綇璐﹀彿瀵嗙爜锛屽悗闈?`xtool auth` 瑕佺敤 |
| iPhone 寮€鍙戣€呮ā寮?| 璁剧疆 鈫?闅愮涓庡畨鍏ㄦ€?鈫?寮€鍙戣€呮ā寮?鈫?寮€ | 寮€鍏冲湪鏈€搴曢儴锛屽紑浜嗚閲嶅惎涓€娆℃墜鏈?|
| 鎵嬭〃寮€鍙戣€呮ā寮?| 鎵嬭〃 璁剧疆 鈫?闅愮涓庡畨鍏ㄦ€?鈫?寮€鍙戣€呮ā寮?鈫?寮€ | **寮€鍏抽粯璁ら殣钘?*锛岄渶鍏堝仛 2.6 鐨?reveal 姝ラ |

---

## 绗?1 閮ㄥ垎 路 Windows 渚ц蒋浠?
### 1.1 瀹夎 Apple Devices锛堟垨 iTunes锛?
浣滅敤锛氭彁渚?`AppleMobileDeviceService`锛屽畠鍦ㄦ湰鏈?`127.0.0.1:27015` 璺?usbmuxd锛屾槸 WSL 涓?iPhone 閫氫俊鐨勬ˉ銆?
- Microsoft Store 鎼?**"Apple Devices"** 瀹夎锛堟垨瑁?iTunes锛夈€?- 鎻?iPhone锛岀瓑 Windows 璇嗗埆锛宨Phone 涓婄偣"淇′换"銆?- 楠岃瘉锛歚netstat -ano | findstr ":27015"` 搴旂湅鍒?`127.0.0.1:27015 LISTENING`锛岃繘绋嬪悕 `AppleMobileDeviceService`銆?
### 1.2 瀹夎 WSL2 + Ubuntu 24.04

PowerShell锛堢鐞嗗憳锛夛細

```powershell
wsl --install -d Ubuntu-24.04
```

瑁呭畬鍚姩涓€娆★紝鍒涘缓 Linux 鐢ㄦ埛锛堝亣璁剧敤鎴峰悕 `champ`锛屽叏绋嬬敤瀹冿級銆?
### 1.3 WSL 缃戝叧鍦板潃锛堝叧閿紒锛?
WSL 涓嶈兘鐩存帴杩?Windows 鐨?127.0.0.1锛岃璧扮綉鍏炽€傛煡缃戝叧 IP锛?
```bash
# WSL 鍐?ip route show default | awk '{print $3}'     # 渚嬪杈撳嚭 172.27.128.1
```

鏈墜鍐岀粺涓€鐢?`USBMUXD_SOCKET_ADDRESS=172.27.128.1:27015`鈥斺€旀妸 IP 鎹㈡垚浣犳煡鍒扮殑缃戝叧銆傚師鐞嗭細Windows 鐨?WSL 杞彂鎶?WSL 缃戝叧鍦板潃涓婄殑绔彛鏄犲皠鍒?Windows localhost 鍚屽悕绔彛锛屼簬鏄?WSL 閲岃繛 `缃戝叧IP:27015` = 杩?Windows 鐨?usbmuxd銆?
---

## 绗?2 閮ㄥ垎 路 WSL 鍐呯幆澧冩惌寤?
### 2.1 鍩虹鏋勫缓宸ュ叿

```bash
sudo apt update
sudo apt install -y build-essential git curl wget pkg-config autoconf automake libtool \
  libssl-dev libplist-dev unzip zip python3 python3-venv python3-pip
```

### 2.2 Swift 6.4.x 宸ュ叿閾?
```bash
# 涓嬭浇 Swift 6.4.1 Ubuntu 24.04 鐗堬紙瀹樼綉 swift.org/install/linux锛?cd /tmp
curl -LO https://download.swift.org/swift-6.4.1-release/ubuntu2404/swift-6.4.1-RELEASE/swift-6.4.1-RELEASE-ubuntu24.04.tar.gz
sudo mkdir -p /opt/swift-6.4.1
sudo tar -xzf swift-6.4.1-RELEASE-ubuntu24.04.tar.gz -C /opt/swift-6.4.1 --strip-components=1
echo 'export PATH=/opt/swift-6.4.1/usr/bin:$PATH' >> ~/.bashrc
export PATH=/opt/swift-6.4.1/usr/bin:$PATH
swift --version   # 搴旇緭鍑?Swift version 6.4.1
```

杩橀渶瑕?Swift 鐨?Linux 杩愯渚濊禆锛堢己浠€涔堟寜鎶ラ敊琛ワ級锛?
```bash
sudo apt install -y binutils gnupg2 libc6-dev libcurl4-openssl-dev libedit2 \
  libgcc-13-dev libpython3-dev libstdc++-13-dev libxml2-dev libz3-dev \
  pkg-config tzdata unzip zlib1g-dev libncurses-dev libsqlite3-dev
```

### 2.3 libimobiledevice 1.4 鍏ㄥ妗讹紙婧愮爜缂栬瘧锛?
xtool 鐨勮澶囦氦浜掑眰渚濊禆杩欎簺搴撶殑鏈€鏂扮増锛圲buntu 婧愰噷鐨勫お鏃э級锛岀紪璇戝埌鐙珛鍓嶇紑锛?
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

**娉ㄦ剰**锛歚--without-tools` 涓嶅甫 `idevice_*` 鍛戒护琛屽伐鍏枫€傛湰鎵嬪唽鐨勮瘖鏂懡浠わ紙`idevice_id`銆乣ideviceinfo`锛夐渶瑕?tools鈥斺€旀妸鏈€鍚庝竴椤?`libimobiledevice` 鐨勬瀯寤哄弬鏁板幓鎺?`--without-tools` 鍐嶇紪涓€娆″嵆鍙紝鎴栧崟鐙 `apt install libimobiledevice-tools` 鍋氳瘖鏂€?
鑷锛坕Phone 瑙ｉ攣浜睆鎻掔潃 USB锛夛細

```bash
export USBMUXD_SOCKET_ADDRESS=172.27.128.1:27015
idevice_id -l                       # 杈撳嚭 <PHONE_UDID>
ideviceinfo -k DeviceName           # 杈撳嚭鎵嬫満鍚?ideviceinfo -k PasswordProtected    # 蹇呴』 false
```

**鍧?*锛歩Phone 閿佸睆鏃?`idevice_id` 浼氬厛鍒楀嚭璁惧闅忓嵆娑堝け锛屾墍鏈夊悗缁懡浠ゆ姤 `No device found`銆傚叏绋嬩繚鎸佹墜鏈鸿В閿併€?
### 2.4 xtool 婧愮爜锛坒ork锛歺tool-watch锛?
```bash
cd ~/Developer
git clone https://github.com/xtool-org/xtool.git xtool-watch-fix
cd xtool-watch-fix && git checkout 1.24.0
```

鐒跺悗鎸?*绗?3 閮ㄥ垎**鎵撹ˉ涓併€?
### 2.5 pymobiledevice3锛堢洿杩炴墜琛ㄧ敤锛?
```bash
python3 -m venv ~/Developer/xtool-watch-device-venv
~/Developer/xtool-watch-device-venv/bin/pip install pymobiledevice3
```

鍐嶆妸 `watch_connection.py` 鍜?`watch_device.py` 涓や釜鏂囦欢鏀惧埌涓€涓洰褰曪紙鏈墜鍐岄厤濂楁枃浠跺湪 `work/watch-device-helper/`锛屽唴瀹硅绗?6 閮ㄥ垎闄勫綍锛夈€?
### 2.6 璁╂墜琛ㄦ樉绀?寮€鍙戣€呮ā寮?寮€鍏筹紙鍏抽敭鍓嶇疆锛屽埆璺宠繃锛?
**鎵嬭〃鐨?寮€鍙戣€呮ā寮?寮€鍏抽粯璁ゆ槸闅愯棌鐨?*鈥斺€斿拰 iPhone 涓€鏍凤紝瑕佸厛鐢ㄤ竴鍙?寮€鍙戞満鍣?杩炰笂鍘昏姹?reveal锛屽紑鍏虫墠浼氬嚭鐜板湪 鎵嬭〃 璁剧疆 鈫?闅愮涓庡畨鍏ㄦ€?閲屻€俶acOS 涓?Xcode 杩炰竴娆″氨鑷姩 reveal锛涙病鏈?Mac 鐨勮瘽鐢?amfi lockdown 鏈嶅姟鎵嬪姩鍙?reveal 璇锋眰锛?
```bash
cd <watch-device-helper鐩綍>
USBMUXD_SOCKET_ADDRESS=172.27.128.1:27015 \
  ~/Developer/xtool-watch-device-venv/bin/python3 \
  watch_device.py --state-directory ~/xtool-tmp/watch-device-state \
  --pair --reveal-developer-mode
```

鎵ц娴佺▼锛氬伐鍏烽€氳繃 iPhone 鐨?companion_proxy 鐩磋繛鎵嬭〃 鈫?棣栨瑙﹀彂鎵嬭〃"淇′换姝ょ數鑴?锛堟埓琛ㄨВ閿佺偣淇′换锛岄厤瀵硅褰曞瓨杩?`--state-directory`锛夆啋 鍚戞墜琛?amfi 鏈嶅姟鍙?`{"action": 0}` reveal 璇锋眰 鈫?鎵撳嵃鎻愮ず銆?
鐒跺悗鍒版墜琛ㄤ笂鎿嶄綔锛?*鎵嬭〃 璁剧疆 鈫?闅愮涓庡畨鍏ㄦ€?鈫?鏈€搴曢儴鐜板湪鍑虹幇"寮€鍙戣€呮ā寮?鈫?鎵撳紑 鈫?鎵嬭〃浼氳姹傞噸鍚?鈫?閲嶅惎鍚庡湪鎵嬭〃涓婄‘璁や竴娆?鍚敤寮€鍙戣€呮ā寮?**銆?
楠岃瘉寮€鍏冲凡鐢熸晥锛?
```bash
watch_device.py --state-directory ~/xtool-tmp/watch-device-state
# 杈撳嚭搴斿惈 "developer_mode": true
```

鑻ヤ负 `false`锛屽洖鍒版墜琛ㄨ缃噷纭寮€鍏崇湡鐨勫紑浜嗕笖閲嶅惎瀹屾垚銆?
---

## 绗?3 閮ㄥ垎 路 xtool 琛ヤ竵锛? 澶勶級

### 3.1 鍏嶈垂璐﹀彿鏀捐 App Groups

`Sources/XKit/DeveloperServices/App IDs/Entitlements/DeveloperServicesCapability.swift`锛?
```swift
extension AppGroupEntitlement: EntitlementWithCapability {
    var capability: DeveloperServicesCapability {
        DeveloperServicesCapability(.appGroups, isFree: true)   // 鍘熶负 false
    }
}
```

### 3.2 缁?Watch bundle 娉ㄥ叆 App Group entitlement

`Sources/XKit/DeveloperServices/App IDs/DeveloperServicesAddAppOperation.swift`锛屽湪 `let appID = try await upsertApp(...)` **涔嬪墠**鎻掑叆锛?
```swift
if isWatch,
   let existing = try? entitlements.entitlements(),
   !existing.contains(where: { $0 is AppGroupEntitlement }) {
    var patched = existing
    patched.append(AppGroupEntitlement(rawValue: [
        .init(rawValue: "<GROUP_ID>")   // 渚嬪 group.com.friend.hermes锛屽繀椤?2瀛楄妭涓斾笌浜岃繘鍒?patch 涓€鑷?    ]))
    try? entitlements.setEntitlements(patched)
}
```

### 3.3 缁?ID 鍘熸牱淇濈暀

`Sources/XKit/DeveloperServices/App Groups/DeveloperServicesAssignAppGroupsOperation.swift`锛屽垱寤虹粍鏃朵笉瑕佸啀鍔犲伐 ID锛?
```swift
let request = DeveloperServicesAddAppGroupRequest(
    platform: .iOS,
    teamID: xcodeAuthData.teamID,
    name: ProvisioningIdentifiers.groupName(fromSanitized: sanitized),
    groupID: groupID          // 鍘熸牱浼狅紝涓嶈鐢?ProvisioningIdentifiers.groupID(fromSanitized:)
)
```

### 3.4 鍓嶆彁锛氭瘡涓唴宓?app 鐙珛鎻忚堪鏂囦欢

`ProvisioningBundle.discover` 蹇呴』閬嶅巻 `Watch/*.app`锛堟爣 `isWatch=true`锛夛紝姣忎釜 bundle 鍗曠嫭璧?App ID + 鎻忚堪鏂囦欢鐢宠锛沗DeveloperServicesFetchProfileOperation` 鍦?`isWatch` 鏃舵妸 **Watch UDID**锛堜笉鏄墜鏈?UDID锛夊姞杩?`ProvisionedDevices`銆傝嫢浣犵殑鍩虹嚎娌℃湁杩欏"per-bundle provisioning"锛屽厛瀹炵幇瀹冣€斺€旇繖鏄墜琛ㄨ寰椾笂鐨勭‖鍓嶆彁銆?
### 3.5 鏋勫缓

```bash
export PATH=/opt/swift-6.4.1/usr/bin:$PATH
cd ~/Developer/xtool-watch-fix
prefix=~/Developer/xtool-native-deps/prefix
swift build --build-system native --pkg-config-path $prefix/lib/pkgconfig -j 4 \
  -Xcc -I$prefix/include -Xlinker -L$prefix/lib \
  -Xlinker -rpath -Xlinker $prefix/lib --product xtool
```

**蹇呴』甯?`--build-system native`**锛屽惁鍒?SwiftyMobileDevice 鎶?`idevice_subscription_context_t` 鎵句笉鍒般€?
鍋氬惎鍔ㄥ櫒锛?
```bash
sudo tee /usr/local/bin/xtool-watch <<'EOF'
#!/bin/sh
export LD_LIBRARY_PATH=$HOME/Developer/xtool-native-deps/prefix/lib
export USBMUXD_SOCKET_ADDRESS=172.27.128.1:27015
exec $HOME/Developer/xtool-watch-fix/.build/debug/xtool "$@"
EOF
sudo chmod +x /usr/local/bin/xtool-watch
```

鐧诲綍 Apple ID锛?
```bash
xtool-watch auth
# 鎸夋彁绀鸿緭鍏?Apple ID 鍜屽瘑鐮侊紙浼氭湁鑻规灉涓ゆ楠岃瘉/璁惧鐮佹祦绋嬶級
xtool-watch auth status    # 纭 Team ID 宸叉嬁鍒?```

---

## 绗?4 閮ㄥ垎 路 澶勭悊 HermesEnabler IPA

### 4.1 涓嬭浇

```bash
cd ~/xtool-tmp || mkdir -p ~/xtool-tmp && cd ~/xtool-tmp
curl -L -o hermes-1.4.1.ipa https://github.com/pookjw/HermesEnabler/releases/download/1.4.1/HermesEnabler.ipa
# 鑻?404锛屽幓 releases 椤甸潰鐪嬪疄闄?asset 鍚?```

### 4.2 鎹?App Group ID锛堝叧閿級

浜岃繘鍒剁‖缂栫爜 `group.com.kamui.escape`锛堝師浣滆€呯殑缁勶紝鍒汉娉ㄥ唽涓嶄簡锛夈€傛崲鎴愪綘璐﹀彿鐙湁鐨?**22 瀛楄妭**缁?ID銆備緥濡?`group.com.friend.hermes`锛堟暟涓€涓嬶細22 瀛楃锛夈€傝窇 `patch-hermes-group.py`锛?
```python
import zipfile, sys
OLD = b'group.com.kamui.escape'
NEW = sys.argv[3].encode()
assert len(NEW) == 22 and NEW.startswith(b'group.'), 'must be 22 bytes starting with group.'
zin = zipfile.ZipFile(sys.argv[1]); zout = zipfile.ZipFile(sys.argv[2], 'w', zipfile.ZIP_DEFLATED)
n = 0
for it in zin.infolist():
    d = zin.read(it.filename)
    if it.filename.endswith(('HermesEnabler2', 'HermesCompanion')):
        c = d.count(OLD)
        if c: d = d.replace(OLD, NEW); n += c; print(it.filename, c)
    zout.writestr(it, d)
zout.close(); print('replaced', n)
```

```bash
python3 patch-hermes-group.py hermes-1.4.1.ipa hermes-1.4.1-grouped.ipa 'group.com.<浣犵殑ID>'
# 棰勬湡杈撳嚭 replaced 2锛坒at 浜岃繘鍒朵袱涓?slice 鍚勪竴澶勶級
```

**杩欎釜 ID 蹇呴』鍜岀 3.2 鑺傝ˉ涓侀噷鐨勫瓧绗︿覆涓€瀛椾笉宸€?*

### 4.3 鎷块厤瀵规墜琛?UDID

鏂规硶 A锛堟渶绠€鍗曪級锛歩Phone 鈫?Watch App 鈫?鎴戠殑鎵嬭〃 鈫?閫氱敤 鈫?鍏充簬 鈫?鐪?UDID锛熸墜琛?UDID 涓嶅湪閭ｉ噷鏄剧ず銆傜敤 B銆?
鏂规硶 B锛氶€氳繃 companion_proxy 璇婚厤瀵硅〃銆傝窇 `watch_device.py`锛堢 6 閮ㄥ垎闄勫綍浠ｇ爜锛夛細

```bash
cd <watch-device-helper鐩綍>
USBMUXD_SOCKET_ADDRESS=172.27.128.1:27015 \
  ~/Developer/xtool-watch-device-venv/bin/python3 \
  watch_device.py --state-directory ~/xtool-tmp/watch-device-state \
  --device-info ~/xtool-tmp/watch-info.json
```

棣栨浼氳Е鍙戞墜琛ㄧ殑"淇′换姝ょ數鑴?鎻愮ず锛屾墜琛ㄤ笂鐐逛俊浠伙紙鎴村湪鎵嬩笂銆佽В閿侊級銆傛垚鍔熷悗 `watch-info.json` 閲屾湁 `udid` 鍜?`name`銆傝涓?`<WATCH_UDID>`銆?
**鍧?*锛氭墜琛ㄧ殑淇′换璁板綍瀛樺湪 `--state-directory` 涓嬶紱鍒犳帀鎴栨崲鐩綍瑕侀噸鏂扮偣淇′换銆?
### 4.4 绛惧悕骞惰鍒?iPhone

```bash
xtool-watch install ~/xtool-tmp/hermes-1.4.1-grouped.ipa \
  --watch-udid <WATCH_UDID> \
  --signed-ipa-output ~/xtool-tmp/hermes-signed.ipa
```

棰勬湡锛歚Provisioning` 闃舵 Apple 缁欎綘鐨勫洟闃熷垱寤?`<GROUP_ID>`锛堝厤璐硅处鍙峰彲浠ュ缓缁勶紝瀹炴祴锛夆啋 `Signing 鈫?Packaging 鈫?Installing 鈫?Verifying 鈫?Successfully installed!`

**瑁呭畬蹇呴』楠岃瘉涓や釜鏂█**锛?
```python
import zipfile, plistlib
z = zipfile.ZipFile('hermes-signed.ipa')
raw = z.read('Payload/HermesCompanion.app/Watch/HermesEnabler2.app/embedded.mobileprovision')
p = plistlib.loads(raw[raw.find(b'<?xml'):raw.find(b'</plist>')+8])
assert '<WATCH_UDID>' in p['ProvisionedDevices']          # 鎵嬭〃UDID鍦ㄥ悕鍗曢噷
assert p['Entitlements']['com.apple.security.application-groups'] == ['<GROUP_ID>']
```

### 4.5 瑁呭埌鎵嬭〃锛堢粫杩?iPhone Watch App锛侊級

iPhone Watch App 鐨?鍙敤 App 鈫?瀹夎"璧板紓姝ュ悓姝ワ紝**澶ф鐜囨姤"鏃犳硶瀹夎锛岃绋嶅悗鍐嶈瘯"**銆傜洿鎺ョ粫锛?
```bash
# 浠庡凡绛?IPA 瑙ｅ嚭鎵嬭〃 app
cd ~/xtool-tmp
unzip -o -q hermes-signed.ipa 'Payload/HermesCompanion.app/Watch/HermesEnabler2.app/*' -d extract
mv 'extract/Payload/HermesCompanion.app/Watch/HermesEnabler2.app' ./HermesEnabler2.app

# 鐩磋繛鎵嬭〃鎺ㄩ€?cd <watch-device-helper鐩綍>
USBMUXD_SOCKET_ADDRESS=172.27.128.1:27015 \
  ~/Developer/xtool-watch-device-venv/bin/python3 \
  watch_device.py --state-directory ~/xtool-tmp/watch-device-state \
  --install ~/xtool-tmp/HermesEnabler2.app
```

杈撳嚭 `Install: 100%` + `Installed and verified` 鍗虫垚鍔熴€?*鎵嬭〃涓婄洿鎺ユ墦寮€ HermesEnabler**銆?
---

## 绗?4B 閮ㄥ垎 路 App Group 閰嶇疆闂璇﹁В锛堜负浠€涔堝繀椤绘敼浜岃繘鍒讹級

杩欏潡鏄暣涓祦绋嬫渶瀹规槗琚瑙ｇ殑閮ㄥ垎锛屽崟鐙娓呮銆?
### 鐥囩姸

鎵嬭〃涓婃墦寮€ HermesEnabler锛宐qtool 鏃ュ織鏈€鍚庝袱琛屾槸锛?
```
app group entitlement: (none)
MobileGestalt Access Failed
An App Group ID may be missing, or this watchOS version may be incompatible.
```

鍘熷洜锛欻ermesEnabler 1.4+ 鍚姩鏃剁敤 `SecTaskCopyValueForEntitlement` 璇?`com.apple.security.application-groups`锛岃涓嶅埌锛坄(none)`锛夊氨璧颁笉涓嬪幓銆?.3 鐗堟湰娌¤繖涓鏌ワ紝鎵€浠?1.3 鑳借窇 1.4 鎶ラ敊"涓嶅鎬€?
### 涓変釜杩炵幆鍧?
**鍧?1锛歺tool 榛樿涓嶇粰 Watch app 鐢宠 App Group銆?*
涓婃父浠ｇ爜 `DeveloperServicesCapability.swift` 閲?`AppGroupEntitlement` 纭紪鐮?`isFree: false`锛屾剰鍛崇潃鍏嶈垂璐﹀彿绛惧悕鏃?App Group entitlement 浼氳杩囨护鎺夆€斺€旀弿杩版枃浠堕噷鏍规湰娌℃湁 `application-groups` 閿€傝ˉ涓?3.1 鎶婂畠鏀惧紑鍗冲彲锛堝疄娴嬪厤璐硅处鍙峰彲浠ユ敞鍐?App Group锛孉pple 鎺ュ彛涓嶆嫤锛夈€?
**鍧?2锛氱粍 ID `group.com.kamui.escape` 琚師浣滆€呭崰鐢ㄤ簡銆?*
App Group ID 鍦?Apple 寮€鍙戣€呬綋绯婚噷**鍏ㄥ眬鍞竴**锛屽厛鍒板厛寰椼€傚氨绠椾綘鏀捐浜?App Group锛屽幓娉ㄥ唽 `group.com.kamui.escape` 涔熶細琚嫆锛?
```
Error(code: 35, reason: "An Application Group with Identifier
'group.com.kamui.escape' is not available. Please enter a different string.")
```

鑰?HermesEnabler 浜岃繘鍒舵妸杩欎釜缁?ID 纭紪鐮佸湪 `__TEXT,__cstring` 閲岋紝鍚姩鏃跺氨鎵惧畠鈥斺€?*涓よ竟蹇呴』涓€鑷?*銆?
**鍧?3锛歺tool 浼?瑙勮寖鍖?缁?ID銆?*
`ProvisioningIdentifiers.groupID(fromSanitized:)` 浼氭妸缁?ID 鏀瑰啓鎴愬甫 `XTL-<TeamID>` 鍓嶇紑鐨勫舰寮忥紝 entitlement 閲岀殑鍊煎拰浜岃繘鍒堕噷鐨勫張瀵逛笉涓婁簡銆傝ˉ涓?3.3 璁╁畠鍘熸牱閫忎紶銆?
### 瑙ｆ硶鐨勫畬鏁撮棴鐜?
1. 閫変竴涓?22 瀛楄妭鐨勮嚜鏈夌粍 ID锛坄group.` 寮€澶达紝濡?`group.com.friend.hermes`锛夆€斺€?*闀垮害蹇呴』涓庡師涓插畬鍏ㄤ竴鑷?*锛屽洜涓轰簩杩涘埗 patch 鏄悓闀垮害瑕嗙洊锛?2. `patch-hermes-group.py` 鎶?IPA 閲屼簩杩涘埗涓ゅ `group.com.kamui.escape` 鏀规垚浣犵殑 ID锛坒at 浜岃繘鍒朵袱涓?slice 鍚勪竴澶勶級锛?3. xtool 琛ヤ竵 3.2 娉ㄥ叆鐨?entitlement 鐢ㄥ悓涓€涓?ID锛?4. 绛惧悕鍚?Apple 浼氬湪浣犲洟闃熶笅娉ㄥ唽璇ョ粍 ID 骞舵妸 `com.apple.security.application-groups: [<GROUP_ID>]` 鍐欒繘 Watch app 鐨勬弿杩版枃浠跺拰浜岃繘鍒剁鍚嶃€?
楠岃瘉锛堣瀹屽繀鍋氾級锛?
```python
import zipfile, plistlib
z = zipfile.ZipFile('hermes-signed.ipa')
d = z.read('Payload/HermesCompanion.app/Watch/HermesEnabler2.app/HermesEnabler2')
assert d.count(b'kamui') == 0                      # 鏃х粍 ID 宸叉竻闄?assert d.count(b'<GROUP_ID>') >= 2                 # 鏂?ID 鍦ㄤ簩杩涘埗绛惧悕+瀛楃涓查噷
raw = z.read('Payload/HermesCompanion.app/Watch/HermesEnabler2.app/embedded.mobileprovision')
p = plistlib.loads(raw[raw.find(b'<?xml'):raw.find(b'</plist>')+8])
assert p['Entitlements']['com.apple.security.application-groups'] == ['<GROUP_ID>']
```

**濡傛灉缁?ID 鏄剧ず姝ｅ父浣?App 浠嶆姤 MobileGestalt**锛氶偅鏄?HermesEnabler 鐨?escape 璺緞鍦ㄨ watchOS 鐗堟湰涓婂け鏁堬紙涓婃父 issue #7锛歸atchOS 26.6.1 璧峰叏閮ㄧ瓥鐣ュけ璐ワ級锛屼笉鏄鍚?App Group 闂鈥斺€旂瓑浣滆€呮洿鏂伴€傞厤銆?
---

## 绗?4C 閮ㄥ垎 路 鎵嬭〃渚?鏃犳硶瀹夎锛岃绋嶅悗鍐嶈瘯"鈥斺€旀垚鍥犱笌瑙ｆ硶

### 鐥囩姸

`xtool-watch install` 杈撳嚭 `Successfully installed!`锛宨Phone 涓婁篃鑳界湅鍒?HermesCompanion銆備絾鎵撳紑 iPhone 鐨?Watch App 鈫?鍙敤 App 鈫?HermesEnabler 鈫?瀹夎锛岃浆鍦堝悗鎻愮ず锛?
> **鏃犳硶瀹夎" HermesEnabler"銆傝绋嶅悗鍐嶈瘯銆?*

鍙嶅閲嶈瘯鏈夋椂鍋跺皵鎴愬姛锛堝伓鍙戞€э級锛屽鏁版儏鍐垫槸鏃犻檺澶辫触锛屼笖 iPhone 鍜屾墜琛ㄤ袱渚ч兘娌℃湁鍙鐨勯敊璇棩蹇椼€?
### 鎴愬洜锛堝厛鐞嗚В锛屽埆鐬庨噸璇曪級

iPhone 涓?瀹夎鎴愬姛"鍙唬琛?*澶栧３ app**锛圚ermesCompanion锛夎涓婁簡銆傚唴宓岀殑 Watch app锛坄Payload/.../Watch/HermesEnabler2.app`锛夋槸鍙︿竴鏉￠€氶亾锛歩Phone 鐨?NanoAppSync/watchd 鎶?app 寮傛鍚屾鍒版墜琛ㄢ€斺€旇繖鏉￠€氶亾瀵逛晶杞?app 鐨勬牎楠岄潪甯镐笉閫忔槑锛?
- 鎵嬭〃澶勪簬浠讳綍**闃诲鐘舵€?*锛堟湭瑙ｉ攣銆佹湭浣╂埓銆佸紑鍙戣€呮ā寮忔湭纭銆侀厤瀵圭紦瀛樿繃鏈熴€佽摑鐗?Wi-Fi 閾捐矾鎶栧姩锛夐兘浼氱洿鎺ュ悙杩欎釜閫氱敤閿欒锛屾病鏈夌粏鑺傦紱
- 鎻忚堪鏂囦欢鏍￠獙澶辫触锛堢己 Watch UDID銆乪ntitlement 涓嶅尮閰嶏級涔熸槸鍚屼竴鍙ヨ瘽锛?- 瀹冧笉鍖哄垎"鏆傛椂鎬уけ璐?鍜?纭畾鎬уけ璐?锛岄噸璇曞彧鏄湪璧岃繍姘斻€?
### 瑙ｆ硶锛氱粫杩囪繖鏉￠€氶亾锛岀洿杩炴墜琛ㄦ帹

绗?4.5 鑺傜粰鍑虹殑灏辨槸杩欎釜闂鐨勬爣鍑嗙瓟妗堚€斺€?*涓嶈渚濊禆 iPhone Watch App 鐨勫悓姝?*锛岄€氳繃 iPhone 鐨?companion_proxy 鐩存帴鎶婃墜琛?lockdown 绔彛 62078 杞彂鍑烘潵锛岀劧鍚庣敤 `streaming_zip_conduit` 鎶婂凡绛惧悕鐨?`.app` 鎺ㄧ粰鎵嬭〃锛?
```bash
# 鍓嶇疆锛歩Phone 瑙ｉ攣浜睆锛涙墜琛ㄦ埓鐫€涓旇В閿侊紱閰嶅缂撳瓨杩樺湪锛?-state-directory 鍒垹锛?cd ~/xtool-tmp
unzip -o -q hermes-signed.ipa 'Payload/HermesCompanion.app/Watch/HermesEnabler2.app/*' -d extract
mv 'extract/Payload/HermesCompanion.app/Watch/HermesEnabler2.app' ./HermesEnabler2.app

cd <watch-device-helper鐩綍>
USBMUXD_SOCKET_ADDRESS=172.27.128.1:27015 \
  ~/Developer/xtool-watch-device-venv/bin/python3 \
  watch_device.py --state-directory ~/xtool-tmp/watch-device-state \
  --install ~/xtool-tmp/HermesEnabler2.app
```

杩欐潯璺緞缁曡繃浜?NanoAppSync锛岀洿鎺ュ鎵嬭〃璁?lockdown 鍗忚锛?*杩涘害閫愮櫨鍒嗘瘮鍙銆佺粨鏋滈€氳繃 installation_proxy Lookup 楠岃瘉**鈥斺€旇娌¤涓婁笉鍐嶆槸榛戠洅銆?
### 鐩磋繛鎺ㄩ€佹湰韬け璐ユ椂鐨勬帓鏌ラ『搴?
1. `{"watch_connected": true, "developer_mode": true}`鈥斺€斿繀椤讳袱椤归兘 true銆俙developer_mode: false` 鈫?鍥?2.6 妫€鏌ユ墜琛ㄥ紑鍏虫槸鍚︾湡鎵撳紑涓旈噸鍚‘璁よ繃锛?2. `The Watch must first trust this PC` 鈫?鍔?`--pair` 閲嶈窇锛屾埓琛ㄨВ閿佸湪鎵嬭〃涓婄偣淇′换锛?3. `Cannot forward Watch lockdown service` / 杩炴帴瓒呮椂 鈫?iPhone 鍜屾墜琛ㄧ殑閰嶅閾捐矾闂锛氭墜琛ㄩ噸寮€钃濈墮銆佹斁杩戞墜鏈恒€乮Phone Watch App 閲岀‘璁?鎴戠殑鎵嬭〃"鍒楄〃閲岃澶囧湪绾匡紱
4. 瀹夎鍒颁竴鍗婃姤 `AppInstallError`/`StreamingZipConduitError` 鈫?澶ф鐜囨槸绛惧悕/鎻忚堪鏂囦欢闂锛屽洖 4.4 璺戦偅涓や釜鏂█锛圵atch UDID 鍦?ProvisionedDevices銆乤pplication-groups  entitlement 姝ｇ‘锛夛紱
5. 涓€鍒囨甯镐絾鎵嬭〃涓婃墦涓嶅紑 鈫?鍥?4B 妫€鏌?App Group銆?
---

## 绗?4D 閮ㄥ垎 路 鍏嶈垂璐﹀彿 7 澶╄繃鏈熶笌缁

### 浼氳繃鏈熺殑鍒板簳鏄粈涔?
鍏嶈垂锛圥ersonal Team锛夌鍚嶄骇鐢熶袱涓湁鏃舵晥鐨勪笢瑗匡細

| 浜х墿 | 鏈夋晥鏈?| 鍒版湡琛ㄧ幇 |
|---|---|---|
| 鎻忚堪鏂囦欢 `embedded.mobileprovision` | **7 澶?* | app 鎵撲笉寮€锛屾垨鎵嬭〃涓婂浘鏍囧彉鐏扮偣涓嶅姩 |
| 寮€鍙戣瘉涔?| ~1 骞?| 涓€鑸棤鎰?|

**App Group 娉ㄥ唽鏈韩涓嶄細杩囨湡**鈥斺€擿<GROUP_ID>` 涓€鏃﹀湪浣犲洟闃熶笅鍒涘缓灏变竴鐩村瓨鍦紝缁鏃?Apple 鐩存帴澶嶇敤锛屼笉闇€瑕侊紙涔熶笉搴旇锛夊啀娉ㄥ唽鏂扮殑銆?
### 缁鎿嶄綔锛堟瘡娆″埌鏈熻窇涓€閬嶏紝绾?5 鍒嗛挓锛?
鍓嶇疆鍜岄娆′竴鏍凤細iPhone 瑙ｉ攣浜睆銆佹墜琛ㄦ埓鐫€瑙ｉ攣銆佺幆澧冨彉閲忛兘鍦ㄣ€傜劧鍚庡彧闇€涓ゆ锛?
```bash
# 1. 閲嶆柊绛惧悕 + 瑁?iPhone锛堝悓涓€涓?grouped IPA锛屼笉鐢ㄥ啀 patch锛?xtool-watch install ~/xtool-tmp/hermes-1.4.1-grouped.ipa \
  --watch-udid <WATCH_UDID> \
  --signed-ipa-output ~/xtool-tmp/hermes-signed.ipa
# 娉ㄦ剰锛氳緭鍑烘枃浠跺凡瀛樺湪浼氬厛鍒犳帀锛屾垨鑰呮崲涓緭鍑哄悕

# 2. 閲嶆柊鐩存帹鎵嬭〃锛坒resh-signed 鐨?.app锛?cd ~/xtool-tmp
unzip -o -q hermes-signed.ipa 'Payload/HermesCompanion.app/Watch/HermesEnabler2.app/*' -d extract2
mv 'extract2/Payload/HermesCompanion.app/Watch/HermesEnabler2.app' ./HermesEnabler2.app

cd <watch-device-helper鐩綍>
USBMUXD_SOCKET_ADDRESS=172.27.128.1:27015 \
  ~/Developer/xtool-watch-device-venv/bin/python3 \
  watch_device.py --state-directory ~/xtool-tmp/watch-device-state \
  --install ~/xtool-tmp/HermesEnabler2.app
```

### 涓嶉渶瑕侀噸鍋氱殑浜?
- 鉂?涓嶇敤閲嶆柊 patch 浜岃繘鍒讹紙`hermes-1.4.1-grouped.ipa` 鐣欑潃澶嶇敤锛?- 鉂?涓嶇敤閲嶆柊娉ㄥ唽 App Group锛堝洟闃熶笅鐨勭粍 ID 姘镐箙鏈夋晥锛?- 鉂?涓嶇敤閲嶆柊 `xtool-watch auth`锛堥櫎闈炵櫥鍑烘垨鎹㈣处鍙凤級
- 鉂?涓嶇敤閲嶆柊鐐规墜琛ㄤ俊浠伙紙`--state-directory` 閲岀殑閰嶅缂撳瓨杩樺湪锛?- 鉂?涓嶇敤閲嶅紑寮€鍙戣€呮ā寮忥紙寮€鍏崇姸鎬佹槸璁惧绾х殑锛?
### 寤鸿锛氭妸缁鍋氭垚鑴氭湰

鎶婁笂闈袱鏉″懡浠ゅ啓鎴愪竴涓?`renew.sh` 鏀?PATH 閲岋紝姣忓懆璺戜竴娆°€備篃鍙互鍦ㄦ棩鍘嗚涓?6 澶╁悗鐨勬彁閱掞紙鐣欎竴澶╀綑閲忥紝閬垮厤鍝ぉ蹇樹簡瀵艰嚧 app 缃㈠伐锛夈€?
---

## 绗?4E 閮ㄥ垎 路 鐜涓庤处鍙峰眰鐨勫叾浣欏潙锛堝鏄撹蹇界暐锛?
### iPhone 鐨勫紑鍙戣€呮ā寮忎篃鏄殣钘忕殑

鍜屾墜琛ㄤ竴鏍凤紝iPhone 鐨?寮€鍙戣€呮ā寮?寮€鍏抽粯璁ょ湅涓嶅埌鈥斺€旇澶囩涓€娆¤寮€鍙戝伐鍏疯繛杩囧悗鎵嶅嚭鐜般€傛湰娴佺▼閲?*绗竴娆¤窇 `xtool-watch install` 閫氬父浼氳嚜鍔ㄨЕ鍙?reveal**锛氳瀹屼竴娆″悗 iPhone 璁剧疆閲屾墠鍑虹幇寮€鍏炽€傛墍浠ユ纭『搴忔槸锛?
1. 鍏堣窇涓€娆?`xtool-watch install`锛堟垨浠讳綍 pymobiledevice3 杩炴帴锛夎Е鍙?reveal锛?2. iPhone 璁剧疆 鈫?闅愮涓庡畨鍏ㄦ€?鈫?寮€鍙戣€呮ā寮忓嚭鐜?鈫?鎵撳紑 鈫?閲嶅惎 鈫?纭锛?3. 涔嬪悗鍐嶈窇瀹夎鎵嶆槸寮€鍙戣€呮ā寮忕敓鏁堢殑鐘舵€併€?
濡傛灉 `xtool-watch install` 鎶?"Developer Mode disabled" 浣嗚缃噷鏍规湰鎵句笉鍒板紑鍏斥€斺€斿氨鏄繕娌¤ reveal銆?
### WSL 缃戝叧 IP 浼氬彉

`172.27.128.1` 鏄?WSL 铏氭嫙浜ゆ崲鏈虹殑 DHCP 鍦板潃锛?*閲嶅惎 WSL 鎴?Windows 鍚庡彲鑳藉彉**銆備笉瑕佸啓姝伙紝姣忔鐢ㄥ墠鏌ワ細

```bash
GATEWAY=$(ip route show default | awk '{print $3}')
export USBMUXD_SOCKET_ADDRESS=$GATEWAY:27015
# 杩為€氭€ч獙璇?timeout 3 bash -c "echo > /dev/tcp/$GATEWAY/27015" && echo ok || echo unreachable
```

`unreachable` 鈫?妫€鏌?Windows 渚?`netstat -ano | findstr :27015` 鏄惁杩樺湪鐩戝惉锛沬Phone 鎷旀帀閲嶆彃銆?
### Apple Devices 鍜?iTunes 鍙兘鐣欎竴涓?
Windows 涓婅杩?iTunes 鍙堣 Apple Devices锛堟垨鍙嶈繃鏉ワ級锛屼袱涓?usbmuxd 瀹炵幇浼氭墦鏋讹細27015 绔彛琚崰浣?iPhone 鏃舵柇鏃惰繛銆?*鍙繚鐣欏叾涓竴涓?*锛屾帹鑽?Apple Devices锛圡icrosoft Store 鐗堬級銆傚鏋滆浜?iTunes 鍙堝嵏杞戒笉骞插噣锛宍AppleMobileDeviceService` 鍙兘娈嬬暀鏃х増椹卞姩鈥斺€旇澶囩鐞嗗櫒閲岀‘璁?`Apple Mobile Device USB Driver` 瀛樺湪涓旂増鏈尮閰嶃€?
`localhostForwarding` 榛樿寮€锛屼絾濡傛灉鏈変汉鍦?`.wslconfig` 閲屽叧浜嗗畠锛學SL 杩炰笉閫氱綉鍏?27015 鈥斺€斿鐢ㄦ柟妗堟槸 Windows 渚?`netsh interface portproxy` 鎴栫洿鎺ユ崲 mirrored 缃戠粶妯″紡銆?
### `xtool auth` 鐨?Apple 2FA

`xtool-watch auth` 鐢?SRP 鐧诲綍 Apple ID銆傚紑浜嗗弻閲嶈璇佺殑璐﹀彿浼氳姹傝緭鍏?*璁惧涓婃敹鍒扮殑 6 浣嶉獙璇佺爜**鈥斺€攊Phone 涓婂脊"鍏佽"鍐嶅～鏁板瓧銆侫pple 浼氳瘽 token 鏈夋晥鏈熸湁闄愶紝闀挎椂闂翠笉鐢ㄥ悗 `xtool` 浼氳姹傞噸鏂?`auth`锛涢绻佸け璐ヤ篃鍙兘瑙﹀彂 Apple 椋庢帶涓存椂閿佸畾锛岄殧鍑犲皬鏃跺啀璇曘€?
### 鍏嶈垂璐﹀彿鐨勯殣钘忛厤棰?
- **App ID 姣忓懆涓婇檺 10 涓?*锛歺tool 姣忎釜 bundle 涓€涓?App ID锛岃澶氫釜涓嶅悓 app 寰堝揩鎵撴弧锛涙墦婊″悗杩欏懆瑁呬笉浜嗘柊 app锛堢画绛句笉鍙楀奖鍝嶏紝鍥犱负 App ID 宸插瓨鍦級銆?- **璁惧娉ㄥ唽**锛氫粯璐硅处鍙锋瘡骞?100 鍙颁笂闄愩€佹瘡骞撮噸缃紱鍏嶈垂璐﹀彿鍚屾牱璁℃暟锛岄绻佹崲鎵嬫満/鎵嬭〃鍙兘鎾為檺銆?- **璇佷功鏁伴噺**锛氬厤璐硅处鍙锋湁鏁堝紑鍙戣瘉涔﹂€氬父鍙 1-2 涓紝`xtool` 鍦ㄦ柊鏈哄櫒涓婂垱寤鸿瘉涔﹀彲鑳藉け璐モ€斺€斿湪鏃ф満鍣ㄤ笂鍚婇攢鍚庡啀寤恒€?
### 鎵嬭〃鐨勭郴缁熺骇閲嶇疆

浠ヤ笅鎿嶄綔浼?*娓呯┖寮€鍙戣€呮ā寮忓拰/鎴栦俊浠昏褰?*锛屼箣鍚庤閲嶈蛋 2.6锛?
- watchOS 澶х増鏈洿鏂帮紙閮ㄥ垎鎯呭喌寮€鍏充繚鐣欙紝浣嗕互瀹為檯涓哄噯锛岃瀹屽厛楠岃瘉 `developer_mode: true`锛?- 鍙栨秷閰嶅閲嶆柊閰嶅锛堝繀娓咃細淇′换 + 寮€鍙戣€呮ā寮?+ 宸茶鐨勪晶杞?app锛?- 鎵嬭〃杩樺師/鎶归櫎

**watchOS 鐗堟湰鍏煎鎬?*锛欻ermesEnabler 澹版槑鏀寔鑼冨洿锛?.4.1 鏄?watchOS 27.0鈥?7.3b1锛夈€備笉鍦ㄨ繖涓寖鍥村唴鐨勭増鏈嵆浣胯涓婁簡锛宔scape 璺緞涔熶笉宸ヤ綔鈥斺€旇繖涓嶆槸绛惧悕闂銆?
### 鎵嬭〃涓婃畫鐣欐棫绛惧悕鐨勫壇鏈?
濡傛灉鎵嬭〃涓婅杩囧師浣滆€呯鍚?鍏朵粬璐﹀彿绛惧悕鐨?HermesEnabler锛堢浉鍚?bundle id锛夛紝鐩存帴鎺ㄤ綘绛剧殑鍓湰鍙兘鍐茬獊銆?*鍏堝湪鎵嬭〃涓婃寜浣忓浘鏍囧垹鎺夋棫鐗?*锛屽啀璺?4.5 鐨勭洿鎺ㄣ€?
### 澶氭墜琛ㄩ厤瀵?
`proxy.list()` 棰勬湡鎭板ソ 1 鍧楅厤瀵规墜琛紝澶氬潡浼氱洿鎺ユ姤閿欍€傛湁澶氬潡琛ㄧ殑璇濇敼 `watch_connection.py` 鐨?`registry[0]` 鎸?UDID 閫夋嫨銆?
### 閰嶅缂撳瓨鍒斁 /mnt/c

`--state-directory` 瀛樻墜琛ㄧ殑閰嶅瀵嗛挜銆傛斁鍦?`/mnt/c/...`锛圵indows 鐩橈級鏈夋潈闄?灞炰富鏄犲皠闂锛屾煇浜?pymobiledevice3 鐗堟湰浼氬啓澶辫触銆?*淇濇寔鍦?Linux 鏂囦欢绯荤粺鍐?*锛坄~/xtool-tmp/watch-device-state`锛夛紝鍒犳帀绛変簬娓呯┖淇′换瑕侀噸鏂伴厤瀵广€?
### IPA 鍐呴儴璺緞浼氶殢鐗堟湰鍙樺寲

`unzip` 鎻愬彇璺緞 `Payload/HermesCompanion.app/Watch/HermesEnabler2.app` 鏄?1.4.1 鐨勭粨鏋勩€傛崲鐗堟湰鍏堢‘璁わ細

```bash
unzip -l hermes-signed.ipa | grep -E '\.app/Info.plist'
# 鎵惧埌瀹為檯璺緞鍐嶆寜瀹冭В
```

### 鍏朵粬灏忓潙

- `--signed-ipa-output` 鏂囦欢宸插瓨鍦ㄤ細鐩存帴鎶ラ敊锛屽厛 `rm` 鎴栨崲鍚嶅瓧锛?- 绯荤粺鏃堕挓鍋忓樊杩囧ぇ浼氬鑷寸鍚嶆牎楠屽け璐モ€斺€斾繚鎸?WSL 鍜?Windows 鏃堕棿鍚屾锛?- `xtool-watch install` 闇€瑕佽澶囧湪绾挎彙鎵嬶紝鍗充娇鍔犱簡 `--sign-only` 绫诲弬鏁帮紝鎵嬫満鏂紑浼氳鍛戒护鎸傛鑰屼笉鏄姤閿欙紙鎵嬫満淇濇寔瑙ｉ攣浜睆锛夛紱
- iPhone 鏇存柊 iOS 鍚庣涓€娆¤繛鎺ュ彲鑳介噸鏂板脊"淇′换"鈥斺€旈噸鏂扮偣涓€娆°€?
---

## 绗?5 閮ㄥ垎 路 鍧戜綅閫熸煡

| 鐜拌薄 | 鍘熷洜 | 瑙ｆ硶 |
|---|---|---|
| `Error 35 ... group.com.kamui.escape is not available` | 缁?ID 琚師浣滆€呭崰鐢?| 绗?4.2 鑺傛崲鑷湁 ID锛堣瑙?4B锛?|
| 杩愯鎶?`app group entitlement: (none)` | App Group entitlement 娌¤繘绛惧悕 | 4B锛氭鏌?3 涓ˉ涓侀兘鎵撲簡銆佺粍 ID 涓ょ涓€鑷?|
| `idevice_subscription_context_t` 缂栬瘧閿?| 灏?`--build-system native` | 绗?3.5 鑺?|
| `No device found` / 璁惧鏃舵湁鏃舵棤 | iPhone 閿佸睆 | 瑙ｉ攣浜睆閲嶆潵 |
| 鎵嬭〃"鏃犳硶瀹夎璇风◢鍚庡啀璇? | iPhone Watch App 鍚屾閫氶亾锛圢anoAppSync锛夊鎵€鏈夊け璐ユ姤鍚屼竴鍙ヨ瘽 | 涓嶈閲嶈瘯锛岀敤 4.5/4C 鐩磋繛瀹夎 |
| 鎵嬭〃"鏃犳硶楠岃瘉鍏跺畬鏁存€? | 鎻忚堪鏂囦欢缂?Watch UDID 鎴?Watch app 鏃犵嫭绔?profile | 妫€鏌?4.4 涓や釜鏂█ |
| 鎵嬭〃璁剧疆閲屾壘涓嶅埌"寮€鍙戣€呮ā寮? | 寮€鍏抽粯璁ら殣钘?| 2.6 鍏堣窇 `--reveal-developer-mode` |
| `--install` 鎶?Enable Developer Mode | 鎵嬭〃寮€鍙戣€呮ā寮忔病鐪熸鎵撳紑/娌＄‘璁?| 鎵嬭〃璁剧疆閲岀‘璁ゅ凡寮€涓旈噸鍚悗鐐硅繃纭 |
| 鎵嬭〃瑕佹眰"淇′换姝ょ數鑴? | 鎵嬭〃閰嶅缂撳瓨鏄柊鐨?| 鎴磋〃瑙ｉ攣锛岀敤 4.5 宸ュ叿瑙﹀彂鍚庣偣淇′换 |
| 杩愯鎶?MobileGestalt 浣嗙粍 ID 鏄剧ず姝ｅ父 | 璇?watchOS 鐗堟湰 escape 璺緞鏈韩澶辨晥锛堜笂娓?issue #7锛?| 闈炵鍚嶉棶棰橈紝绛変綔鑰呮洿鏂?|
| `swift: command not found` | 鏂?shell 娌?source PATH | `export PATH=/opt/swift-6.4.1/usr/bin:$PATH` |
| 7 澶╁悗 app 鎵撲笉寮€ | 鍏嶈垂璐﹀彿鎻忚堪鏂囦欢杩囨湡锛堢粍 ID/淇′换/寮€鍙戣€呮ā寮忛兘杩樺湪锛?| 鍙渶 4D 涓ゆ缁锛屼笉鐢ㄩ噸澶村啀鏉?|

---

## 绗?6 閮ㄥ垎 路 闄勫綍锛歸atch_device.py 渚濊禆鐨勪袱浠芥枃浠?
### `watch_connection.py`

```python
import asyncio
from pathlib import Path
from pymobiledevice3.lockdown import PlistUsbmuxLockdownClient, create_using_usbmux
from pymobiledevice3.service_connection import ServiceConnection
from pymobiledevice3.services.companion import CompanionProxyService

class CompanionWatchLockdownClient(PlistUsbmuxLockdownClient):
    def __init__(self, *args, phone, proxy, ports, **kwargs):
        super().__init__(*args, **kwargs)
        self.phone, self.proxy, self.ports = phone, proxy, ports
    async def create_service_connection(self, remote_port):
        local_port = await asyncio.wait_for(self.proxy.start_forwarding_service_port(remote_port), 8)
        if local_port is None:
            raise RuntimeError("Cannot forward requested Watch service.")
        self.ports.add(remote_port)
        return await asyncio.wait_for(ServiceConnection.create_using_usbmux(self.phone.udid, local_port), 8)

class WatchConnection:
    def __init__(self, directory: Path, pair_watch=False):
        self.directory, self.pair_watch = directory, pair_watch
        self.phone = self.watch = self.proxy = self.initial_service = None
        self.ports = set()
    async def __aenter__(self):
        try:
            self.phone = await asyncio.wait_for(create_using_usbmux(autopair=False, connection_type="USB"), 8)
            self.proxy = CompanionProxyService(self.phone)
            registry = await asyncio.wait_for(self.proxy.list(), 8)
            if len(registry) != 1:
                raise RuntimeError("Expected exactly one paired Watch.")
            port = await asyncio.wait_for(self.proxy.start_forwarding_service_port(62078), 8)
            if port is None:
                raise RuntimeError("Cannot forward Watch lockdown service.")
            self.ports.add(62078)
            cache = self.directory / "watch-pairing"
            service = await asyncio.wait_for(ServiceConnection.create_using_usbmux(self.phone.udid, port), 8)
            self.initial_service = service
            self.watch = await asyncio.wait_for(CompanionWatchLockdownClient.create(
                service, identifier=registry[0], port=62078, autopair=False,
                pairing_records_cache_folder=cache, system_buid=self.phone.system_buid,
                phone=self.phone, proxy=self.proxy, ports=self.ports), 15)
            if not self.watch.paired and self.pair_watch:
                await asyncio.wait_for(self.watch.pair(timeout=30), 35)
            if not self.watch.paired:
                raise RuntimeError("The Watch must first trust this PC.")
            if self.watch.all_values.get("DeviceClass") != "Watch":
                raise RuntimeError("Connection did not reach an Apple Watch.")
            return self.watch
        except BaseException:
            await self.__aexit__(None, None, None)
            raise
    async def __aexit__(self, *_):
        try:
            if self.watch is not None:
                await asyncio.wait_for(self.watch.close(), 5)
            elif self.initial_service is not None:
                await asyncio.wait_for(self.initial_service.close(), 5)
        finally:
            try:
                if self.proxy is not None:
                    for port in sorted(self.ports, reverse=True):
                        try:
                            await asyncio.wait_for(self.proxy.stop_forwarding_service_port(port), 5)
                        except Exception:
                            pass
                    await asyncio.wait_for(self.proxy.close(), 5)
            finally:
                if self.phone is not None:
                    await asyncio.wait_for(self.phone.close(), 5)
```

### `watch_device.py`

```python
import argparse, asyncio, json
from pathlib import Path
import plistlib
from zipfile import ZipFile
from pymobiledevice3.services.installation_proxy import InstallationProxyService
from pymobiledevice3.services.streaming_zip_conduit import StreamingZipConduitService
from watch_connection import WatchConnection

def package_info(package):
    if package.is_dir() and package.suffix == ".app":
        info = plistlib.loads((package / "Info.plist").read_bytes())
    else:
        with ZipFile(package) as archive:
            candidates = [n for n in archive.namelist()
                          if n.startswith("Payload/") and n.count("/") == 2 and n.endswith("/Info.plist")]
            if len(candidates) != 1:
                raise ValueError("Expected a single Watch app payload.")
            info = plistlib.loads(archive.read(candidates[0]))
    if info.get("WKApplication") is not True or info.get("CFBundleSupportedPlatforms") != ["WatchOS"]:
        raise ValueError("Expected a watchOS device app.")
    return info

async def main(args):
    info = package_info(args.install) if args.install else None
    async with WatchConnection(args.state_directory, pair_watch=args.pair) as watch:
        enabled = await watch.get_developer_mode_status()
        print(json.dumps({"watch_connected": True, "developer_mode": enabled}), flush=True)
        if args.device_info:
            with args.device_info.open("x", encoding="utf-8") as f:
                json.dump({"udid": watch.all_values["UniqueDeviceID"],
                           "name": watch.all_values.get("DeviceName", "Apple Watch")}, f)
        if info is None:
            return
        if not enabled:
            raise RuntimeError("Enable Developer Mode on the Watch first.")
        async with StreamingZipConduitService(watch) as conduit:
            await conduit.install(args.install, developer=True,
                                  handler=lambda v: print(f"Install: {v}%", flush=True))
        async with InstallationProxyService(watch) as installer:
            result = await installer.service.send_recv_plist(
                {"Command": "Lookup", "ClientOptions": {"BundleIDs": [info["CFBundleIdentifier"]]}})
            if info["CFBundleIdentifier"] not in result.get("LookupResult", {}):
                raise RuntimeError("Install completed but lookup failed.")
        print("Installed and verified in the Watch app registry.", flush=True)

def run():
    p = argparse.ArgumentParser()
    p.add_argument("--state-directory", type=Path, default=Path(".watchos"))
    p.add_argument("--pair", action="store_true")
    p.add_argument("--device-info", type=Path)
    p.add_argument("--install", type=Path)
    args = p.parse_args()
    args.state_directory.mkdir(parents=True, exist_ok=True)
    try:
        asyncio.run(asyncio.wait_for(main(args), 120))
    except Exception as e:
        if isinstance(e, (ValueError, RuntimeError)) or type(e).__name__ in {"AppInstallError", "StreamingZipConduitError"}:
            print(str(e), flush=True)
        print(f"Deployment stopped: {type(e).__name__}", flush=True)
        raise SystemExit(1)

if __name__ == "__main__":
    run()
```

涓ゆ枃浠舵斁鍚屼竴鐩綍锛宍watch_device.py` import `watch_connection`銆?
---

## 涓€鍙ヨ瘽鎬荤粨娴佺▼

瑁?Apple Devices 鈫?瑁?WSL+Swift+libimobiledevice 鈫?clone xtool 鎵?3 涓ˉ涓佸苟鏋勫缓 鈫?`xtool-watch auth` 鐧诲綍 鈫?patch IPA 閲岀殑缁?ID 鈫?`xtool-watch install` 瑁?iPhone 鈫?鐢?`watch_device.py` 鐩磋繛鎵嬭〃鎺ㄩ€?.app 鈫?鎵嬭〃鎵撳紑銆?
---

**浣滆€?*锛氬皬绾功 [@champ](https://xhslink.cn/o/6M9yj7X0RCn) 路 瀹炴祴鐜 watchOS 27.2 / iOS 27.0.1 / 鍏嶈垂 Apple ID
