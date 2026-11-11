# HermesEnabler 装到 Apple Watch 全流程手册（Windows + WSL + 免费 Apple 账号，零 Mac）

**[English](README.md) | 中文**

> **给 AI agent 的说明**：这是一份从头开始的完整操作手册，不要跳过任何"自检"步骤。
> 所有路径里的 `champ`、`<DEPS_PREFIX>`、`<WATCH_UDID>`、`<PHONE_UDID>`、`<GROUP_ID>` 是占位符，按实际值替换。
> 已验证环境：Windows 11 + WSL2 Ubuntu 24.04、Swift 6.4.1、libimobiledevice 1.4.0、iPhone（iOS 26.x）、Apple Watch（watchOS 27.2）、免费 Apple ID。

---

## 第 0 部分 · 硬件与账号准备

| 项 | 要求 | 检查方法 |
|---|---|---|
| 电脑 | Windows 10/11，能用 WSL2 | `wsl --status` |
| iPhone | USB 连电脑，点过"信任此电脑" | 插线后 iPhone 弹信任框 |
| Apple Watch | 已与 iPhone 配对，佩戴且解锁 | 手表能正常看表盘 |
| Apple 账号 | **免费** Apple ID 即可，无需付费开发者 | 记住账号密码，后面 `xtool auth` 要用 |
| iPhone 开发者模式 | 设置 → 隐私与安全性 → 开发者模式 → 开 | 开关在最底部，开了要重启一次手机 |
| 手表开发者模式 | 手表 设置 → 隐私与安全性 → 开发者模式 → 开 | 同上 |

---

## 第 1 部分 · Windows 侧软件

### 1.1 安装 Apple Devices（或 iTunes）

作用：提供 `AppleMobileDeviceService`，它在本机 `127.0.0.1:27015` 跑 usbmuxd，是 WSL 与 iPhone 通信的桥。

- Microsoft Store 搜 **"Apple Devices"** 安装（或装 iTunes）。
- 插 iPhone，等 Windows 识别，iPhone 上点"信任"。
- 验证：`netstat -ano | findstr ":27015"` 应看到 `127.0.0.1:27015 LISTENING`，进程名 `AppleMobileDeviceService`。

### 1.2 安装 WSL2 + Ubuntu 24.04

PowerShell（管理员）：

```powershell
wsl --install -d Ubuntu-24.04
```

装完启动一次，创建 Linux 用户（假设用户名 `champ`，全程用它）。

### 1.3 WSL 网关地址（关键！）

WSL 不能直接连 Windows 的 127.0.0.1，要走网关。查网关 IP：

```bash
# WSL 内
ip route show default | awk '{print $3}'     # 例如输出 172.27.128.1
```

本手册统一用 `USBMUXD_SOCKET_ADDRESS=172.27.128.1:27015`——把 IP 换成你查到的网关。原理：Windows 的 WSL 转发把 WSL 网关地址上的端口映射到 Windows localhost 同名端口，于是 WSL 里连 `网关IP:27015` = 连 Windows 的 usbmuxd。

---

## 第 2 部分 · WSL 内环境搭建

### 2.1 基础构建工具

```bash
sudo apt update
sudo apt install -y build-essential git curl wget pkg-config autoconf automake libtool \
  libssl-dev libplist-dev unzip zip python3 python3-venv python3-pip
```

### 2.2 Swift 6.4.x 工具链

```bash
# 下载 Swift 6.4.1 Ubuntu 24.04 版（官网 swift.org/install/linux）
cd /tmp
curl -LO https://download.swift.org/swift-6.4.1-release/ubuntu2404/swift-6.4.1-RELEASE/swift-6.4.1-RELEASE-ubuntu24.04.tar.gz
sudo mkdir -p /opt/swift-6.4.1
sudo tar -xzf swift-6.4.1-RELEASE-ubuntu24.04.tar.gz -C /opt/swift-6.4.1 --strip-components=1
echo 'export PATH=/opt/swift-6.4.1/usr/bin:$PATH' >> ~/.bashrc
export PATH=/opt/swift-6.4.1/usr/bin:$PATH
swift --version   # 应输出 Swift version 6.4.1
```

还需要 Swift 的 Linux 运行依赖（缺什么按报错补）：

```bash
sudo apt install -y binutils gnupg2 libc6-dev libcurl4-openssl-dev libedit2 \
  libgcc-13-dev libpython3-dev libstdc++-13-dev libxml2-dev libz3-dev \
  pkg-config tzdata unzip zlib1g-dev libncurses-dev libsqlite3-dev
```

### 2.3 libimobiledevice 1.4 全家桶（源码编译）

xtool 的设备交互层依赖这些库的最新版（Ubuntu 源里的太旧），编译到独立前缀：

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

**注意**：`--without-tools` 不带 `idevice_*` 命令行工具。本手册的诊断命令（`idevice_id`、`ideviceinfo`）需要 tools——把最后一项 `libimobiledevice` 的构建参数去掉 `--without-tools` 再编一次即可，或单独装 `apt install libimobiledevice-tools` 做诊断。

自检（iPhone 解锁亮屏插着 USB）：

```bash
export USBMUXD_SOCKET_ADDRESS=172.27.128.1:27015
idevice_id -l                       # 输出 <PHONE_UDID>
ideviceinfo -k DeviceName           # 输出手机名
ideviceinfo -k PasswordProtected    # 必须 false
```

**坑**：iPhone 锁屏时 `idevice_id` 会先列出设备随即消失，所有后续命令报 `No device found`。全程保持手机解锁。

### 2.4 xtool 源码（fork：xtool-watch）

```bash
cd ~/Developer
git clone https://github.com/xtool-org/xtool.git xtool-watch-fix
cd xtool-watch-fix && git checkout 1.24.0
```

然后按**第 3 部分**打补丁。

### 2.5 pymobiledevice3（直连手表用）

```bash
python3 -m venv ~/Developer/xtool-watch-device-venv
~/Developer/xtool-watch-device-venv/bin/pip install pymobiledevice3
```

再把 `watch_connection.py` 和 `watch_device.py` 两个文件放到一个目录（本手册配套文件在 `work/watch-device-helper/`，内容见第 6 部分附录）。

---

## 第 3 部分 · xtool 补丁（3 处）

### 3.1 免费账号放行 App Groups

`Sources/XKit/DeveloperServices/App IDs/Entitlements/DeveloperServicesCapability.swift`：

```swift
extension AppGroupEntitlement: EntitlementWithCapability {
    var capability: DeveloperServicesCapability {
        DeveloperServicesCapability(.appGroups, isFree: true)   // 原为 false
    }
}
```

### 3.2 给 Watch bundle 注入 App Group entitlement

`Sources/XKit/DeveloperServices/App IDs/DeveloperServicesAddAppOperation.swift`，在 `let appID = try await upsertApp(...)` **之前**插入：

```swift
if isWatch,
   let existing = try? entitlements.entitlements(),
   !existing.contains(where: { $0 is AppGroupEntitlement }) {
    var patched = existing
    patched.append(AppGroupEntitlement(rawValue: [
        .init(rawValue: "<GROUP_ID>")   // 例如 group.com.friend.hermes，必须22字节且与二进制 patch 一致
    ]))
    try? entitlements.setEntitlements(patched)
}
```

### 3.3 组 ID 原样保留

`Sources/XKit/DeveloperServices/App Groups/DeveloperServicesAssignAppGroupsOperation.swift`，创建组时不要再加工 ID：

```swift
let request = DeveloperServicesAddAppGroupRequest(
    platform: .iOS,
    teamID: xcodeAuthData.teamID,
    name: ProvisioningIdentifiers.groupName(fromSanitized: sanitized),
    groupID: groupID          // 原样传，不要用 ProvisioningIdentifiers.groupID(fromSanitized:)
)
```

### 3.4 前提：每个内嵌 app 独立描述文件

`ProvisioningBundle.discover` 必须遍历 `Watch/*.app`（标 `isWatch=true`），每个 bundle 单独走 App ID + 描述文件申请；`DeveloperServicesFetchProfileOperation` 在 `isWatch` 时把 **Watch UDID**（不是手机 UDID）加进 `ProvisionedDevices`。若你的基线没有这套"per-bundle provisioning"，先实现它——这是手表装得上的硬前提。

### 3.5 构建

```bash
export PATH=/opt/swift-6.4.1/usr/bin:$PATH
cd ~/Developer/xtool-watch-fix
prefix=~/Developer/xtool-native-deps/prefix
swift build --build-system native --pkg-config-path $prefix/lib/pkgconfig -j 4 \
  -Xcc -I$prefix/include -Xlinker -L$prefix/lib \
  -Xlinker -rpath -Xlinker $prefix/lib --product xtool
```

**必须带 `--build-system native`**，否则 SwiftyMobileDevice 报 `idevice_subscription_context_t` 找不到。

做启动器：

```bash
sudo tee /usr/local/bin/xtool-watch <<'EOF'
#!/bin/sh
export LD_LIBRARY_PATH=$HOME/Developer/xtool-native-deps/prefix/lib
export USBMUXD_SOCKET_ADDRESS=172.27.128.1:27015
exec $HOME/Developer/xtool-watch-fix/.build/debug/xtool "$@"
EOF
sudo chmod +x /usr/local/bin/xtool-watch
```

登录 Apple ID：

```bash
xtool-watch auth
# 按提示输入 Apple ID 和密码（会有苹果两步验证/设备码流程）
xtool-watch auth status    # 确认 Team ID 已拿到
```

---

## 第 4 部分 · 处理 HermesEnabler IPA

### 4.1 下载

```bash
cd ~/xtool-tmp || mkdir -p ~/xtool-tmp && cd ~/xtool-tmp
curl -L -o hermes-1.4.1.ipa https://github.com/nicegram/HermesEnabler/releases/download/1.4.1/HermesEnabler.ipa
# 若 404，去 releases 页面看实际 asset 名
```

### 4.2 换 App Group ID（关键）

二进制硬编码 `group.com.kamui.escape`（原作者的组，别人注册不了）。换成你账号独有的 **22 字节**组 ID。例如 `group.com.friend.hermes`（数一下：22 字符）。跑 `patch-hermes-group.py`：

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
python3 patch-hermes-group.py hermes-1.4.1.ipa hermes-1.4.1-grouped.ipa 'group.com.<你的ID>'
# 预期输出 replaced 2（fat 二进制两个 slice 各一处）
```

**这个 ID 必须和第 3.2 节补丁里的字符串一字不差。**

### 4.3 拿配对手表 UDID

方法 A（最简单）：iPhone → Watch App → 我的手表 → 通用 → 关于 → 看 UDID？手表 UDID 不在那里显示。用 B。

方法 B：通过 companion_proxy 读配对表。跑 `watch_device.py`（第 6 部分附录代码）：

```bash
cd <watch-device-helper目录>
USBMUXD_SOCKET_ADDRESS=172.27.128.1:27015 \
  ~/Developer/xtool-watch-device-venv/bin/python3 \
  watch_device.py --state-directory ~/xtool-tmp/watch-device-state \
  --device-info ~/xtool-tmp/watch-info.json
```

首次会触发手表的"信任此电脑"提示，手表上点信任（戴在手上、解锁）。成功后 `watch-info.json` 里有 `udid` 和 `name`。记下 `<WATCH_UDID>`。

**坑**：手表的信任记录存在 `--state-directory` 下；删掉或换目录要重新点信任。

### 4.4 签名并装到 iPhone

```bash
xtool-watch install ~/xtool-tmp/hermes-1.4.1-grouped.ipa \
  --watch-udid <WATCH_UDID> \
  --signed-ipa-output ~/xtool-tmp/hermes-signed.ipa
```

预期：`Provisioning` 阶段 Apple 给你的团队创建 `<GROUP_ID>`（免费账号可以建组，实测）→ `Signing → Packaging → Installing → Verifying → Successfully installed!`

**装完必须验证两个断言**：

```python
import zipfile, plistlib
z = zipfile.ZipFile('hermes-signed.ipa')
raw = z.read('Payload/HermesCompanion.app/Watch/HermesEnabler2.app/embedded.mobileprovision')
p = plistlib.loads(raw[raw.find(b'<?xml'):raw.find(b'</plist>')+8])
assert '<WATCH_UDID>' in p['ProvisionedDevices']          # 手表UDID在名单里
assert p['Entitlements']['com.apple.security.application-groups'] == ['<GROUP_ID>']
```

### 4.5 装到手表（绕过 iPhone Watch App！）

iPhone Watch App 的"可用 App → 安装"走异步同步，**大概率报"无法安装，请稍后再试"**。直接绕：

```bash
# 从已签 IPA 解出手表 app
cd ~/xtool-tmp
unzip -o -q hermes-signed.ipa 'Payload/HermesCompanion.app/Watch/HermesEnabler2.app/*' -d extract
mv 'extract/Payload/HermesCompanion.app/Watch/HermesEnabler2.app' ./HermesEnabler2.app

# 直连手表推送
cd <watch-device-helper目录>
USBMUXD_SOCKET_ADDRESS=172.27.128.1:27015 \
  ~/Developer/xtool-watch-device-venv/bin/python3 \
  watch_device.py --state-directory ~/xtool-tmp/watch-device-state \
  --install ~/xtool-tmp/HermesEnabler2.app
```

输出 `Install: 100%` + `Installed and verified` 即成功。**手表上直接打开 HermesEnabler**。

---

## 第 5 部分 · 坑位速查

| 现象 | 原因 | 解法 |
|---|---|---|
| `Error 35 ... group.com.kamui.escape is not available` | 组 ID 被原作者占用 | 第 4.2 节换自有 ID |
| `idevice_subscription_context_t` 编译错 | 少 `--build-system native` | 第 3.5 节 |
| `No device found` / 设备时有时无 | iPhone 锁屏 | 解锁亮屏重来 |
| 手表"无法安装请稍后再试" | iPhone Watch App 同步通道问题 | 第 4.5 节直连安装 |
| 手表"无法验证其完整性" | 描述文件缺 Watch UDID 或 Watch app 无独立 profile | 检查 4.4 两个断言 |
| 手表要求"信任此电脑" | 手表配对缓存是新的 | 戴表解锁，用 4.5 工具触发后点信任 |
| 运行报 MobileGestalt 但组 ID 显示正常 | 该 watchOS 版本 escape 路径本身失效（上游 issue #7） | 非签名问题，等作者更新 |
| `swift: command not found` | 新 shell 没 source PATH | `export PATH=/opt/swift-6.4.1/usr/bin:$PATH` |
| 7 天后 app 打不开 | 免费账号证书过期 | 重跑 4.4 + 4.5 |

---

## 第 6 部分 · 附录：watch_device.py 依赖的两份文件

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

两文件放同一目录，`watch_device.py` import `watch_connection`。

---

## 一句话总结流程

装 Apple Devices → 装 WSL+Swift+libimobiledevice → clone xtool 打 3 个补丁并构建 → `xtool-watch auth` 登录 → patch IPA 里的组 ID → `xtool-watch install` 装 iPhone → 用 `watch_device.py` 直连手表推送 .app → 手表打开。
