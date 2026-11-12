# HermesEnabler 装到 Apple Watch 全流程手册（Windows + WSL + 免费 Apple 账号，零 Mac）

**中文 | [English](README.en.md)**

> **致谢**：本教程只是侧载方法——真正的功臣是 [HermesEnabler](https://github.com/pookjw/HermesEnabler) 及其原作者 **pookjw**（Jinwoo Kim）。没有他做的表盘绕过工具，就没有这个教程存在的意义。
>
> **执行工具建议**：推荐用 **DeepSeek Harness**（dsh）跑本流程——整套工作流涉及二进制 patch、Apple 签名、设备直连等操作，Codex 等受严格安全协议约束的 agent 会在中途被拦截或要求逐步审批，打断流程。DeepSeek Harness 提供 unrestricted sandbox 模式，能顺畅跑完。
>
> **给 AI agent 的说明**：这是一份从头开始的完整操作手册，不要跳过任何"自检"步骤。
> 所有路径里的 `champ`、`<DEPS_PREFIX>`、`<WATCH_UDID>`、`<PHONE_UDID>`、`<GROUP_ID>` 是占位符，按实际值替换。
> 已验证环境：Windows 11 + WSL2 Ubuntu 24.04、Swift 6.4.1、libimobiledevice 1.4.0、iPhone（iOS 27.0.1）、Apple Watch（watchOS 27.2）、免费 Apple ID。

---

## 🚀 一键安装

### 方式 A · Windows 图形界面（推荐）

下载 **[HermesInstaller.exe](https://github.com/champion0399/hermes-watch-windows/releases/latest/download/HermesInstaller.exe)**（当前 **v1.3.0**，约 717 KiB），双击运行；窗口标题可核对版本。

它会：
1. 首次安装时请求管理员权限
2. 检查/安装 **Apple Devices**（iPhone 驱动，走 winget）
3. 检查/安装 **WSL + Ubuntu 24.04**，处理需要重启的情况
4. 复用既有普通用户，或在全新 Ubuntu 中创建用户；保留现有 WSL 配置
5. 校验 USB 转发，部署 EXE 内嵌的完整安装资源，在终端中执行安装

按终端提示完成开发者模式确认、Apple ID 登录及可能的 2FA、App Group ID 等输入；已有有效会话会复用。脚本负责环境编译、签名和装表。

**验证范围**：97 项 Python 回归、82 项 Windows 回归通过；真实签名缓存及 GUI→WSL 只读状态链路已检查。新版真实设备续签/升级成功路径及空白 Windows 完整安装仍待实机验证。详情见 [续签升级测试报告](MANAGEMENT-TEST-REPORT.md) 与 [首次安装测试报告](FIRST-INSTALL-TEST-REPORT.md)。

**界面下方还有三个按钮**（装完后管理用）：

| 按钮 | 干什么 |
|---|---|
| **续签 (7天)** | 保留当前缓存中的应用版本，重新签名并安装到手表；校验描述文件有效期和设备安装收据。复用有效的 Apple ID 会话，失效时提示重新登录。 |
| **升级最新版** | 从原作者 Release 获取最新 IPA，校验下载、patch、签名并安装；仅在手表校验成功后记录版本和更新缓存。 |
| **状态** | 显示历史成功安装的上游版本、本地签名包到期时间，并只读查询手表中的应用；设备字段固定为 1.0 时与上游版本分开显示。 |

### 方式 B · WSL 命令行（已装好 WSL 的用户）

```bash
curl -sL https://raw.githubusercontent.com/champion0399/hermes-watch-windows/main/install.sh | bash
```

下面是手动执行的完整版（想理解每一步或一键脚本出问题时按这个走）。

---

## 第 0 部分 · 硬件与账号准备

| 项 | 要求 | 检查方法 |
|---|---|---|
| 电脑 | Windows 10/11，能用 WSL2 | `wsl --status` |
| iPhone | USB 连电脑，点过"信任此电脑" | 插线后 iPhone 弹信任框 |
| Apple Watch | 已与 iPhone 配对，佩戴且解锁 | 手表能正常看表盘 |
| Apple 账号 | **免费** Apple ID 即可，无需付费开发者 | 记住账号密码，后面 `xtool auth` 要用 |
| iPhone 开发者模式 | 设置 → 隐私与安全性 → 开发者模式 → 开 | 开关在最底部，开了要重启一次手机 |
| 手表开发者模式 | 手表 设置 → 隐私与安全性 → 开发者模式 → 开 | **开关默认隐藏**，需先做 2.6 的 reveal 步骤 |

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

### 2.6 让手表显示"开发者模式"开关（关键前置，别跳过）

**手表的"开发者模式"开关默认是隐藏的**——和 iPhone 一样，要先用一台"开发机器"连上去请求 reveal，开关才会出现在 手表 设置 → 隐私与安全性 里。macOS 上 Xcode 连一次就自动 reveal；没有 Mac 的话用 amfi lockdown 服务手动发 reveal 请求：

```bash
cd <watch-device-helper目录>
USBMUXD_SOCKET_ADDRESS=172.27.128.1:27015 \
  ~/Developer/xtool-watch-device-venv/bin/python3 \
  watch_device.py --state-directory ~/xtool-tmp/watch-device-state \
  --pair --reveal-developer-mode
```

执行流程：工具通过 iPhone 的 companion_proxy 直连手表 → 首次触发手表"信任此电脑"（戴表解锁点信任，配对记录存进 `--state-directory`）→ 向手表 amfi 服务发 `{"action": 0}` reveal 请求 → 打印提示。

然后到手表上操作：**手表 设置 → 隐私与安全性 → 最底部现在出现"开发者模式"→ 打开 → 手表会要求重启 → 重启后在手表上确认一次"启用开发者模式"**。

验证开关已生效：

```bash
watch_device.py --state-directory ~/xtool-tmp/watch-device-state
# 输出应含 "developer_mode": true
```

若为 `false`，回到手表设置里确认开关真的开了且重启完成。

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

### 4.1 下载（始终拉取原作者最新版）

原作者 pookjw 更新很勤快，**不要写死版本号**。自动拿最新 release 的 IPA：

```bash
mkdir -p ~/xtool-tmp && cd ~/xtool-tmp

# 从 GitHub API 取最新 release 的 IPA 下载地址
URL=$(curl -s https://api.github.com/repos/pookjw/HermesEnabler/releases/latest | \
  grep -o 'https://[^"]*HermesEnabler[^"]*\.ipa' | head -1)
echo "Latest: $URL"
curl -L -o hermes-latest.ipa "$URL"
```

如果 API 拿到的是 `.app` 或 `.zip`，先看里面有什么再处理。手动方式：打开 https://github.com/pookjw/HermesEnabler/releases/latest 看 asset 名再下载。

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
python3 patch-hermes-group.py hermes-latest.ipa hermes-grouped.ipa 'group.com.<你的ID>'
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
xtool-watch install ~/xtool-tmp/hermes-grouped.ipa \
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

## 第 4B 部分 · App Group 配置问题详解（为什么必须改二进制）

这块是整个流程最容易被误解的部分，单独说清楚。

### 症状

手表上打开 HermesEnabler，bqtool 日志最后两行是：

```
app group entitlement: (none)
MobileGestalt Access Failed
An App Group ID may be missing, or this watchOS version may be incompatible.
```

原因：HermesEnabler 1.4+ 启动时用 `SecTaskCopyValueForEntitlement` 读 `com.apple.security.application-groups`，读不到（`(none)`）就走不下去。1.3 版本没这个检查，所以"1.3 能跑 1.4 报错"不奇怪。

### 三个连环坑

**坑 1：xtool 默认不给 Watch app 申请 App Group。**
上游代码 `DeveloperServicesCapability.swift` 里 `AppGroupEntitlement` 硬编码 `isFree: false`，意味着免费账号签名时 App Group entitlement 会被过滤掉——描述文件里根本没有 `application-groups` 键。补丁 3.1 把它放开即可（实测免费账号可以注册 App Group，Apple 接口不拦）。

**坑 2：组 ID `group.com.kamui.escape` 被原作者占用了。**
App Group ID 在 Apple 开发者体系里**全局唯一**，先到先得。就算你放行了 App Group，去注册 `group.com.kamui.escape` 也会被拒：

```
Error(code: 35, reason: "An Application Group with Identifier
'group.com.kamui.escape' is not available. Please enter a different string.")
```

而 HermesEnabler 二进制把这个组 ID 硬编码在 `__TEXT,__cstring` 里，启动时就找它——**两边必须一致**。

**坑 3：xtool 会"规范化"组 ID。**
`ProvisioningIdentifiers.groupID(fromSanitized:)` 会把组 ID 改写成带 `XTL-<TeamID>` 前缀的形式， entitlement 里的值和二进制里的又对不上了。补丁 3.3 让它原样透传。

### 解法的完整闭环

1. 选一个 22 字节的自有组 ID（`group.` 开头，如 `group.com.friend.hermes`）——**长度必须与原串完全一致**，因为二进制 patch 是同长度覆盖；
2. `patch-hermes-group.py` 把 IPA 里二进制两处 `group.com.kamui.escape` 改成你的 ID（fat 二进制两个 slice 各一处）；
3. xtool 补丁 3.2 注入的 entitlement 用同一个 ID；
4. 签名后 Apple 会在你团队下注册该组 ID 并把 `com.apple.security.application-groups: [<GROUP_ID>]` 写进 Watch app 的描述文件和二进制签名。

验证（装完必做）：

```python
import zipfile, plistlib
z = zipfile.ZipFile('hermes-signed.ipa')
d = z.read('Payload/HermesCompanion.app/Watch/HermesEnabler2.app/HermesEnabler2')
assert d.count(b'kamui') == 0                      # 旧组 ID 已清除
assert d.count(b'<GROUP_ID>') >= 2                 # 新 ID 在二进制签名+字符串里
raw = z.read('Payload/HermesCompanion.app/Watch/HermesEnabler2.app/embedded.mobileprovision')
p = plistlib.loads(raw[raw.find(b'<?xml'):raw.find(b'</plist>')+8])
assert p['Entitlements']['com.apple.security.application-groups'] == ['<GROUP_ID>']
```

**如果组 ID 显示正常但 App 仍报 MobileGestalt**：那是 HermesEnabler 的 escape 路径在该 watchOS 版本上失效（上游 issue #7：watchOS 26.6.1 起全部策略失败），不是签名/App Group 问题——等作者更新适配。

---

## 第 4C 部分 · 手表侧"无法安装，请稍后再试"——成因与解法

### 症状

`xtool-watch install` 输出 `Successfully installed!`，iPhone 上也能看到 HermesCompanion。但打开 iPhone 的 Watch App → 可用 App → HermesEnabler → 安装，转圈后提示：

> **无法安装" HermesEnabler"。请稍后再试。**

反复重试有时偶尔成功（偶发性），多数情况是无限失败，且 iPhone 和手表两侧都没有可读的错误日志。

### 成因（先理解，别瞎重试）

iPhone 上"安装成功"只代表**外壳 app**（HermesCompanion）装上了。内嵌的 Watch app（`Payload/.../Watch/HermesEnabler2.app`）是另一条通道：iPhone 的 NanoAppSync/watchd 把 app 异步同步到手表——这条通道对侧载 app 的校验非常不透明：

- 手表处于任何**阻塞状态**（未解锁、未佩戴、开发者模式未确认、配对缓存过期、蓝牙/Wi-Fi 链路抖动）都会直接吐这个通用错误，没有细节；
- 描述文件校验失败（缺 Watch UDID、entitlement 不匹配）也是同一句话；
- 它不区分"暂时性失败"和"确定性失败"，重试只是在赌运气。

### 解法：绕过这条通道，直连手表推

第 4.5 节给出的就是这个问题的标准答案——**不要依赖 iPhone Watch App 的同步**，通过 iPhone 的 companion_proxy 直接把手表 lockdown 端口 62078 转发出来，然后用 `streaming_zip_conduit` 把已签名的 `.app` 推给手表：

```bash
# 前置：iPhone 解锁亮屏；手表戴着且解锁；配对缓存还在（--state-directory 别删）
cd ~/xtool-tmp
unzip -o -q hermes-signed.ipa 'Payload/HermesCompanion.app/Watch/HermesEnabler2.app/*' -d extract
mv 'extract/Payload/HermesCompanion.app/Watch/HermesEnabler2.app' ./HermesEnabler2.app

cd <watch-device-helper目录>
USBMUXD_SOCKET_ADDRESS=172.27.128.1:27015 \
  ~/Developer/xtool-watch-device-venv/bin/python3 \
  watch_device.py --state-directory ~/xtool-tmp/watch-device-state \
  --install ~/xtool-tmp/HermesEnabler2.app
```

这条路径绕过了 NanoAppSync，直接对手表讲 lockdown 协议，**进度逐百分比可见、结果通过 installation_proxy Lookup 验证**——装没装上不再是黑盒。

### 直连推送本身失败时的排查顺序

1. `{"watch_connected": true, "developer_mode": true}`——必须两项都 true。`developer_mode: false` → 回 2.6 检查手表开关是否真打开且重启确认过；
2. `The Watch must first trust this PC` → 加 `--pair` 重跑，戴表解锁在手表上点信任；
3. `Cannot forward Watch lockdown service` / 连接超时 → iPhone 和手表的配对链路问题：手表重开蓝牙、放近手机、iPhone Watch App 里确认"我的手表"列表里设备在线；
4. 安装到一半报 `AppInstallError`/`StreamingZipConduitError` → 大概率是签名/描述文件问题，回 4.4 跑那两个断言（Watch UDID 在 ProvisionedDevices、application-groups  entitlement 正确）；
5. 一切正常但手表上打不开 → 回 4B 检查 App Group。

---

## 第 4D 部分 · 免费账号 7 天过期与续签

### 会过期的到底是什么

免费（Personal Team）签名产生两个有时效的东西：

| 产物 | 有效期 | 到期表现 |
|---|---|---|
| 描述文件 `embedded.mobileprovision` | **7 天** | app 打不开，或手表上图标变灰点不动 |
| 开发证书 | ~1 年 | 一般无感 |

**App Group 注册本身不会过期**——`<GROUP_ID>` 一旦在你团队下创建就一直存在，续签时 Apple 直接复用，不需要（也不应该）再注册新的。

### 续签操作（每次到期跑一遍，约 5 分钟）

前置和首次一样：iPhone 解锁亮屏、手表戴着解锁、环境变量都在。然后只需两步：

```bash
# 1. 重新签名 + 装 iPhone（同一个 grouped IPA，不用再 patch）
xtool-watch install ~/xtool-tmp/hermes-1.4.1-grouped.ipa \
  --watch-udid <WATCH_UDID> \
  --signed-ipa-output ~/xtool-tmp/hermes-signed.ipa
# 注意：输出文件已存在会先删掉，或者换个输出名

# 2. 重新直推手表（fresh-signed 的 .app）
cd ~/xtool-tmp
unzip -o -q hermes-signed.ipa 'Payload/HermesCompanion.app/Watch/HermesEnabler2.app/*' -d extract2
mv 'extract2/Payload/HermesCompanion.app/Watch/HermesEnabler2.app' ./HermesEnabler2.app

cd <watch-device-helper目录>
USBMUXD_SOCKET_ADDRESS=172.27.128.1:27015 \
  ~/Developer/xtool-watch-device-venv/bin/python3 \
  watch_device.py --state-directory ~/xtool-tmp/watch-device-state \
  --install ~/xtool-tmp/HermesEnabler2.app
```

### 不需要重做的事

- ❌ 不用重新 patch 二进制（`hermes-grouped.ipa` 留着复用，同一版本内）
- ❌ 不用重新注册 App Group（团队下的组 ID 永久有效）
- ❌ 不用重新 `xtool-watch auth`（除非登出或换账号）
- ❌ 不用重新点手表信任（`--state-directory` 里的配对缓存还在）
- ❌ 不用重开开发者模式（开关状态是设备级的）

### 建议：把续签做成脚本

把上面两条命令写成一个 `renew.sh` 放 PATH 里，每周跑一次。也可以在日历设个 6 天后的提醒（留一天余量，避免哪天忘了导致 app 罢工）。

---

## 第 4E 部分 · 环境与账号层的其余坑（容易被忽略）

### iPhone 的开发者模式也是隐藏的

和手表一样，iPhone 的"开发者模式"开关默认看不到——设备第一次被开发工具连过后才出现。本流程里**第一次跑 `xtool-watch install` 通常会自动触发 reveal**：装完一次后 iPhone 设置里才出现开关。所以正确顺序是：

1. 先跑一次 `xtool-watch install`（或任何 pymobiledevice3 连接）触发 reveal；
2. iPhone 设置 → 隐私与安全性 → 开发者模式出现 → 打开 → 重启 → 确认；
3. 之后再跑安装才是开发者模式生效的状态。

如果 `xtool-watch install` 报 "Developer Mode disabled" 但设置里根本找不到开关——就是还没被 reveal。

### WSL 网关 IP 会变

`172.27.128.1` 是 WSL 虚拟交换机的 DHCP 地址，**重启 WSL 或 Windows 后可能变**。不要写死，每次用前查：

```bash
GATEWAY=$(ip route show default | awk '{print $3}')
export USBMUXD_SOCKET_ADDRESS=$GATEWAY:27015
# 连通性验证
timeout 3 bash -c "echo > /dev/tcp/$GATEWAY/27015" && echo ok || echo unreachable
```

`unreachable` → 检查 Windows 侧 `netstat -ano | findstr :27015` 是否还在监听；iPhone 拔掉重插。

### Apple Devices 和 iTunes 只能留一个

Windows 上装过 iTunes 又装 Apple Devices（或反过来），两个 usbmuxd 实现会打架：27015 端口被占但 iPhone 时断时连。**只保留其中一个**，推荐 Apple Devices（Microsoft Store 版）。如果装了 iTunes 又卸载不干净，`AppleMobileDeviceService` 可能残留旧版驱动——设备管理器里确认 `Apple Mobile Device USB Driver` 存在且版本匹配。

`localhostForwarding` 默认开，但如果有人在 `.wslconfig` 里关了它，WSL 连不通网关 27015 ——备用方案是 Windows 侧 `netsh interface portproxy` 或直接换 mirrored 网络模式。

### `xtool auth` 的 Apple 2FA

`xtool-watch auth` 用 SRP 登录 Apple ID。开了双重认证的账号会要求输入**设备上收到的 6 位验证码**——iPhone 上弹"允许"再填数字。Apple 会话 token 有效期有限，长时间不用后 `xtool` 会要求重新 `auth`；频繁失败也可能触发 Apple 风控临时锁定，隔几小时再试。

### 免费账号的隐藏配额

- **App ID 每周上限 10 个**：xtool 每个 bundle 一个 App ID，装多个不同 app 很快打满；打满后这周装不了新 app（续签不受影响，因为 App ID 已存在）。
- **设备注册**：付费账号每年 100 台上限、每年重置；免费账号同样计数，频繁换手机/手表可能撞限。
- **证书数量**：免费账号有效开发证书通常只容 1-2 个，`xtool` 在新机器上创建证书可能失败——在旧机器上吊销后再建。

### 手表的系统级重置

以下操作会**清空开发者模式和/或信任记录**，之后要重走 2.6：

- watchOS 大版本更新（部分情况开关保留，但以实际为准，装完先验证 `developer_mode: true`）
- 取消配对重新配对（必清：信任 + 开发者模式 + 已装的侧载 app）
- 手表还原/抹除

**watchOS 版本兼容性**：HermesEnabler 声明支持范围（1.4.1 是 watchOS 27.0–27.3b1）。不在这个范围内的版本即使装上了，escape 路径也不工作——这不是签名问题。

### 手表上残留旧签名的副本

如果手表上装过原作者签名/其他账号签名的 HermesEnabler（相同 bundle id），直接推你签的副本可能冲突。**先在手表上按住图标删掉旧版**，再跑 4.5 的直推。

### 多手表配对

`proxy.list()` 预期恰好 1 块配对手表，多块会直接报错。有多块表的话改 `watch_connection.py` 的 `registry[0]` 按 UDID 选择。

### 配对缓存别放 /mnt/c

`--state-directory` 存手表的配对密钥。放在 `/mnt/c/...`（Windows 盘）有权限/属主映射问题，某些 pymobiledevice3 版本会写失败。**保持在 Linux 文件系统内**（`~/xtool-tmp/watch-device-state`），删掉等于清空信任要重新配对。

### IPA 内部路径会随版本变化

`unzip` 提取路径 `Payload/HermesCompanion.app/Watch/HermesEnabler2.app` 是 1.4.1 的结构。换版本先确认：

```bash
unzip -l hermes-signed.ipa | grep -E '\.app/Info.plist'
# 找到实际路径再按它解
```

### 其他小坑

- `--signed-ipa-output` 文件已存在会直接报错，先 `rm` 或换名字；
- 系统时钟偏差过大会导致签名校验失败——保持 WSL 和 Windows 时间同步；
- `xtool-watch install` 需要设备在线握手，即使加了 `--sign-only` 类参数，手机断开会让命令挂死而不是报错（手机保持解锁亮屏）；
- iPhone 更新 iOS 后第一次连接可能重新弹"信任"——重新点一次。

---

## 第 5 部分 · App 功能与设置总览（1.4.1，基于源码）

原作者 README 只写了安装方法，没列功能。以下为源码（`HermesEnabler2/` 下 Swift/ObjC）里的完整清单，所有开关最终都是改 MobileGestalt（MG）缓存里的"能力声明"。

### 表盘（Watch Faces）

| 开关 | MG 字段 | 作用 | 注意 |
|---|---|---|---|
| Hermès | `DeviceBrand` + `fuKL2rMywRgQF1wowOA/cg` | 品牌伪造成 Hermès Edition → 解锁爱马仕表盘 | 核心；改完重启 Carousel 生效 |
| Ultra Faces | `main-screen-class` + `fdh+s6j3VijuyrK7xLjd7g` | 屏幕类别伪造成 Ultra → 解锁 Ultra 表盘 | ⚠️ 与 Hermès 冲突：开 Ultra 用不了 Faubourg Party |

### 显示（Display）

| 开关 | MG 键 | 作用 |
|---|---|---|
| Always-On Display | `2OOJf1VhaM7NxfRok3HbWQ` + `j8/Omm6s1lsmTDFsXjsBfA` | 声明支持常显屏 |
| AOD 1 Hz | `aoJSd/MXk7M40NgXTM6x+g` | 常显 1Hz 刷新（S9+ 特性） |
| AOD Vibrancy | `ykpu7qyhqFweVMKtxNylWA` | 常显鲜艳模式（S9+） |
| Periodic ALS Updates | `Leuy56dCZmAMYoVCQGTfPA` | 环境光周期更新 |
| 分辨率覆盖 | `g7YQ1Djxh4YiKlEeaoGhzg` + `OjzOua0LkOegX7pQdgMksw` | 改 MG 上报屏幕尺寸，6 档预设 | ⚠️ 危险：改错 UI 超大/裁剪（issue #28），需重启，可还原 |

### 操控（Controls）

| 开关 | MG 键 | 作用 |
|---|---|---|
| Action Button | `FBw/2WrPE2supEKosxxoTw` | 声明有 Ultra 操作按钮 |
| Double Tap | `l1CWke97nbaAcWDqA6T5LA` | 双指互点手势（S9+） |
| On-Screen Keyboard | `MQJ1mlVrhOwaUUVJehJSVA` | 屏幕键盘（S7+） |
| Raise Wrist to Wake | `nmOy2K5HzAAs2QNAi8wR+Q` | 抬腕唤醒 |
| Raise to Speak | `4D8XW4YwJI7QvyPhv1TEdw` | 抬腕直接 Siri（S3+） |
| Siri Listening Capability | `U+73bmG4kBGj6kpreQXUTQ` | "嘿 Siri"常听 |

### 传感器与体能（Sensors & Workouts）

| 开关 | MG 键 | 对应硬件 |
|---|---|---|
| Depth Sensor | `Ijs+pw5tRyxqSy5kfgZNuQ` | Ultra 深度计 |
| Absolute Altimeter | `PFnuFyqMMnGUQQnTqS5byg` | 绝对高度计（S8+/Ultra） |
| Always-On Compass | `aCQx2Qq/TChnNAq1rr6Egw` | 常驻指南针（SE2+） |
| Compass Orienteering | `GPIs61LYNpcwZqwlFr7bbg` | 定向越野（Ultra Waypoints） |
| Continuous Heart Rate | `W2RPjaqovtsgiRB6ScePGA` | 持续心率 |
| Noise Exposure | `SaW+DA+cbiqDHrex8MTABA` | 噪声监测（S4+） |
| Battery Information | `Kao6GNYdAy5hwXblxeGYJQ` | 电池健康 |
| Swimming Workouts | `cRjPy4Ef+KZwJ+nfPeBV5Q` | 游泳训练 |

⚠️ 这一整组只是"能力声明"，**不会变出不存在的传感器**——没有深度计的表开了也测不了水深。

### Siri 与智能（Siri & Intelligence）

| 选项 | MG 键 | 作用 |
|---|---|---|
| Region Code | `h63QSdBCiT/z0WU6rdQv6Q` | 设备区域码：美/港/日/国行/台/英/加 |
| Sales Region | `zHeENZu+wbg7PUprwNwBWg` + `yK+xavymRGZ3xWc1tb8XDg` | 销售地区后缀（LL/A、ZA/A 等） |
| Apple Intelligence / Siri AI | `A62OafQ85EJAiiqKn4agtg` | 声明苹果智能（需配对 iPhone 也支持） |
| On-Device Siri | `K/R1GfGfCkXvEhaPS2Vrng` | 设备端 Siri |
| Audio Intelligence | `rb2tKZxlj0Gm2tBmUQSLqQ` | 音频智能（仅 Series 12 / Ultra 4 有效） |

### 备份（MG Backups）

- **首次强制**：任何改动前先建"初始备份"，受保护不可覆盖
- **三层**：`initial`（首次）→ `auto-*`（每次写入前自动）→ `manual-*`（手动）
- **还原校验**：对比 `CacheUUID` 和 `CacheData` 长度，不匹配拒绝写（防止把别的表/别的系统的备份刷进去）

### 隐藏机制（UI 没有，源码才有）

- **BQEscape 6 策略**：class13-direct / class13-traversal / class7-symlink / class2-stage / class2-subpath / class2-parent，全失败才报 MobileGestalt Access Failed
- **Class-2 fallback**（实验）：无 App Group 的备选 escape，27.2 上不可靠
- **NeoSpring**：改完表盘后注入隐藏 WKWebView 重启 Carousel，免整机重启
- **bqtool.log**：escape 过程日志写到 Documents/bqtool.log
- **MGOffsets/MGDefaults plist**：每个支持的 build 一份偏移表 + CacheUUID，不在表里直接拒绝写（"不支持此版本"的来源）

### 关键限制

1. 只认 `MGOffsets` 里 `RecoveryVerified` 的 build；2. flag ≠ 硬件；3. Hermès 与 Ultra 互斥；4. 备份绑定 build，watchOS 更新后旧备份可能失效；5. iPhone 伴侣 app 是空壳，只有"去手表打开"引导页。

---

## 第 6 部分 · 坑位速查

| 现象 | 原因 | 解法 |
|---|---|---|
| `Error 35 ... group.com.kamui.escape is not available` | 组 ID 被原作者占用 | 第 4.2 节换自有 ID（详见 4B） |
| 运行报 `app group entitlement: (none)` | App Group entitlement 没进签名 | 4B：检查 3 个补丁都打了、组 ID 两端一致 |
| `idevice_subscription_context_t` 编译错 | 少 `--build-system native` | 第 3.5 节 |
| `No device found` / 设备时有时无 | iPhone 锁屏 | 解锁亮屏重来 |
| 手表"无法安装请稍后再试" | iPhone Watch App 同步通道（NanoAppSync）对所有失败报同一句话 | 不要重试，用 4.5/4C 直连安装 |
| 手表"无法验证其完整性" | 描述文件缺 Watch UDID 或 Watch app 无独立 profile | 检查 4.4 两个断言 |
| 手表设置里找不到"开发者模式" | 开关默认隐藏 | 2.6 先跑 `--reveal-developer-mode` |
| `--install` 报 Enable Developer Mode | 手表开发者模式没真正打开/没确认 | 手表设置里确认已开且重启后点过确认 |
| 手表要求"信任此电脑" | 手表配对缓存是新的 | 戴表解锁，用 4.5 工具触发后点信任 |
| 运行报 MobileGestalt 但组 ID 显示正常 | 该 watchOS 版本 escape 路径本身失效（上游 issue #7） | 非签名问题，等作者更新 |
| `swift: command not found` | 新 shell 没 source PATH | `export PATH=/opt/swift-6.4.1/usr/bin:$PATH` |
| 7 天后 app 打不开 | 免费账号描述文件过期（组 ID/信任/开发者模式都还在） | 只需 4D 两步续签，不用重头再来 |

---

## 第 7 部分 · 附录：watch_device.py 依赖的两份文件

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

---

**作者**：小红书 [@champ](https://xhslink.cn/o/6M9yj7X0RCn) · 实测环境 watchOS 27.2 / iOS 27.0.1 / 免费 Apple ID

---

## 免责声明

本教程仅供个人学习与设备折腾参考。**按本教程操作所产生的一切后果由操作者自行承担**，包括但不限于：

- 设备变砖、数据丢失、系统损坏、保修失效；
- Apple 账号被封禁、开发者账号受限、证书吊销；
- 手表与 iPhone 配对异常、应用闪退、功能失效；
- 因违反 Apple 开发者协议、App Store 条款或当地法律法规产生的任何责任；
- 任何直接、间接、附带或后果性损失。

使用者应自行评估风险并确保操作合法合规。作者不提供任何形式的担保，也不对教程的准确性、完整性、时效性或适用性作任何承诺。使用即表示你已阅读并同意自行承担全部风险。
