#!/bin/bash
# ============================================================
# HermesEnabler → Apple Watch · 一键安装脚本（Windows + WSL）
# One-click installer: HermesEnabler to Apple Watch via xtool
#
# 用法 / Usage (inside WSL):
#   chmod +x install.sh && ./install.sh
#
# 前置 / Prerequisites:
#   - Windows 装了 Apple Devices（Microsoft Store）或 iTunes
#   - iPhone USB 连接并点过"信任"
#   - iPhone 与手表配对，手表戴着且解锁
#   - 免费 Apple ID
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[1;33m'; CYN='\033[0;36m'; NC='\033[0m'
say()  { echo -e "${CYN}[*]${NC} $*"; }
ok()   { echo -e "${GRN}[✓]${NC} $*"; }
warn() { echo -e "${YEL}[!]${NC} $*"; }
die()  { echo -e "${RED}[✗]${NC} $*"; exit 1; }
ask()  { echo -en "${YEL}[?]${NC} $* "; }

DEPS="$HOME/Developer/xtool-native-deps"
PREFIX="$DEPS/prefix"
SRC="$HOME/Developer/xtool-watch-src"
VENV="$HOME/Developer/xtool-watch-venv"
HELPER="$HOME/Developer/watch-device-helper"
STATE="$HOME/xtool-tmp/watch-device-state"
WORK="$HOME/xtool-tmp"
PATCH_URL="https://raw.githubusercontent.com/champion0399/hermes-watch-windows/main/patches/xtool-watch-1.24.0.patch"
HELPER_URL="https://raw.githubusercontent.com/champion0399/hermes-watch-windows/main/watch-device-helper"

export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export LD_LIBRARY_PATH="$PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

GATEWAY=$(ip route show default | awk '{print $3}')
export USBMUXD_SOCKET_ADDRESS="$GATEWAY:27015"

say "WSL gateway: $GATEWAY"
say "工作目录: $WORK"
mkdir -p "$WORK"

# ---------- 0. 设备连通性 ----------
say "0/8 检查 usbmuxd 连通性（iPhone 需解锁亮屏）"
if ! timeout 4 bash -c "echo > /dev/tcp/$GATEWAY/27015" 2>/dev/null; then
  die "连不上 $GATEWAY:27015 — 检查 Windows 是否装了 Apple Devices/iTunes、iPhone 是否插好并解锁"
fi
ok "usbmuxd reachable"

# ---------- 1. 系统依赖 ----------
say "1/8 安装系统依赖（需要 sudo）"
sudo apt-get update -qq
sudo apt-get install -y -qq build-essential git curl wget pkg-config autoconf automake libtool \
  libssl-dev libplist-dev unzip zip python3 python3-venv python3-pip jq \
  binutils gnupg2 libc6-dev libcurl4-openssl-dev libedit2 libgcc-13-dev \
  libpython3-dev libstdc++-13-dev libxml2-dev libz3-dev tzdata zlib1g-dev \
  libncurses-dev libsqlite3-dev libimobiledevice-utils 2>/dev/null || \
sudo apt-get install -y -qq build-essential git curl wget pkg-config autoconf automake libtool \
  libssl-dev unzip zip python3 python3-venv python3-pip jq
ok "apt deps"

# ---------- 2. Swift ----------
if ! command -v swift >/dev/null 2>&1 || ! swift --version 2>/dev/null | grep -q '6\.4'; then
  say "2/8 安装 Swift 6.4.1"
  cd /tmp
  curl -L -o swift.tgz "https://download.swift.org/swift-6.4.1-release/ubuntu2404/swift-6.4.1-RELEASE/swift-6.4.1-RELEASE-ubuntu24.04.tar.gz"
  sudo mkdir -p /opt/swift-6.4.1
  sudo tar -xzf swift.tgz -C /opt/swift-6.4.1 --strip-components=1
  rm swift.tgz
else
  say "2/8 Swift 已装，跳过"
fi
export PATH="/opt/swift-6.4.1/usr/bin:$PATH"
swift --version | head -1

# ---------- 3. libimobiledevice ----------
if [ ! -f "$DEPS/.deps-done" ]; then
  say "3/8 编译 libimobiledevice 1.4 全家桶（约 10 分钟）"
  mkdir -p "$DEPS/src" "$PREFIX"
  build_dep() {
    local project=$1 version=$2 src=$DEPS/src/$project
    [ -d "$src/.git" ] || git clone --depth 1 --branch "$version" "https://github.com/libimobiledevice/$project.git" "$src"
    cd "$src" && ./autogen.sh --prefix="$PREFIX" --without-cython --without-tools && make -j4 && make install
  }
  build_dep libplist 2.6.0
  build_dep libimobiledevice-glue 1.3.1
  build_dep libusbmuxd 2.1.0
  build_dep libtatsu 1.0.4
  build_dep libimobiledevice 1.4.0
  touch "$DEPS/.deps-done"
else
  say "3/8 libimobiledevice 已装，跳过"
fi
ok "native deps"

idevice_id -l >/dev/null 2>&1 || die "看不到 iPhone — 解锁亮屏重试"
PHONE_UDID=$(idevice_id -l | head -1)
ok "iPhone: $PHONE_UDID"
[ "$(ideviceinfo -k PasswordProtected 2>/dev/null)" = "false" ] || warn "iPhone 处于锁定状态，请解锁"

# ---------- 4. xtool 源码 + 补丁 ----------
if [ ! -f "$SRC/.patch-applied" ]; then
  say "4/8 拉取 xtool 1.24.0 并打补丁"
  rm -rf "$SRC"
  git clone --depth 1 --branch 1.24.0 https://github.com/xtool-org/xtool.git "$SRC"
  cd "$SRC"
  curl -sL "$PATCH_URL" -o /tmp/xtool-watch.patch
  git apply --check /tmp/xtool-watch.patch || die "补丁与 1.24.0 不匹配"
  git apply /tmp/xtool-watch.patch
  touch .patch-applied
else
  say "4/8 xtool 源码已就绪，跳过"
  cd "$SRC"
fi

if [ ! -f "$SRC/.build/release/xtool" ] && [ ! -f "$SRC/.build/debug/xtool" ]; then
  say "   编译 xtool（首次约 15-25 分钟，吃 CPU）"
  swift build --build-system native --pkg-config-path "$PREFIX/lib/pkgconfig" -j 4 \
    -Xcc -I"$PREFIX/include" -Xlinker -L"$PREFIX/lib" \
    -Xlinker -rpath -Xlinker "$PREFIX/lib" --product xtool
else
  say "   xtool 已编译，跳过"
fi
XTOOL_BIN="$SRC/.build/debug/xtool"
[ -x "$SRC/.build/release/xtool" ] && XTOOL_BIN="$SRC/.build/release/xtool"
ok "xtool built: $XTOOL_BIN"

xtool_watch() {
  LD_LIBRARY_PATH="$PREFIX/lib" USBMUXD_SOCKET_ADDRESS="$USBMUXD_SOCKET_ADDRESS" \
    "$XTOOL_BIN" "$@"
}

# ---------- 5. pymobiledevice3 + 手表工具 ----------
say "5/8 准备 pymobiledevice3 与手表工具"
[ -d "$VENV" ] || python3 -m venv "$VENV"
"$VENV/bin/pip" -q install --upgrade pip pymobiledevice3
mkdir -p "$HELPER" "$STATE"
curl -sL "$HELPER_URL/watch_connection.py" -o "$HELPER/watch_connection.py"
curl -sL "$HELPER_URL/watch_device.py" -o "$HELPER/watch_device.py"
ok "watch helper ready"

# ---------- 6. 开发者模式 reveal ----------
say "6/8 揭示 iPhone 与手表的开发者模式开关"
warn "如手表/手机设置里还没有'开发者模式'开关，接下来这步会让它出现"
"$VENV/bin/python" "$HELPER/watch_device.py" --state-directory "$STATE" --pair --reveal-developer-mode 2>&1 | tail -6
warn "请到 手表 设置→隐私与安全性→开发者模式 打开开关并重启确认；iPhone 同样位置也开一次"
ask "开发者模式都已开启并重启确认？(y/N)"
read -r yn; [[ "$yn" =~ ^[Yy] ]] || die "先开开发者模式再重跑"

# ---------- 7. Apple ID 登录 + 组 ID ----------
say "7/8 Apple ID 登录与 App Group"
if ! xtool_watch auth status 2>/dev/null | grep -q 'Team'; then
  say "登录 Apple ID（会触发 2FA）"
  xtool_watch auth
fi
ok "Apple ID signed in"

ask "输入 App Group ID（22 字符，group. 开头，回车用默认 group.com.$USER.hermes）:"
read -r GID
GID=${GID:-"group.com.$USER.hermes"}
[ "${#GID}" -eq 22 ] && [[ "$GID" == group.* ]] || die "组 ID 必须恰好 22 字符且以 group. 开头，当前: '$GID' (${#GID} 字符)"
# 补丁里的占位也要改（如果补丁用了占位符）
if grep -q 'group.com.champ.hermes' "$SRC/Sources/XKit/DeveloperServices/App IDs/DeveloperServicesAddAppOperation.swift" 2>/dev/null; then
  sed -i "s/group\.com\.champ\.hermes/$GID/" "$SRC/Sources/XKit/DeveloperServices/App IDs/DeveloperServicesAddAppOperation.swift"
  say "已把 entitlement 组 ID 同步为 $GID，重新编译增量部分"
  swift build --build-system native --pkg-config-path "$PREFIX/lib/pkgconfig" -j 4 \
    -Xcc -I"$PREFIX/include" -Xlinker -L"$PREFIX/lib" \
    -Xlinker -rpath -Xlinker "$PREFIX/lib" --product xtool
fi
ok "Group ID: $GID"

# ---------- 8. 下载、patch、签名、安装 ----------
say "8/8 下载最新 HermesEnabler、patch 组 ID、签名并安装"
cd "$WORK"
URL=$(curl -s https://api.github.com/repos/pookjw/HermesEnabler/releases/latest | \
  grep -o 'https://[^"]*\.ipa' | head -1)
[ -n "$URL" ] || die "拿不到最新 release 地址"
say "Latest: $URL"
curl -L -o hermes-latest.ipa "$URL"

python3 - "$GID" <<'PYEOF'
import zipfile, sys
GID = sys.argv[1].encode()
OLD = b'group.com.kamui.escape'
zin = zipfile.ZipFile('hermes-latest.ipa'); zout = zipfile.ZipFile('hermes-grouped.ipa', 'w', zipfile.ZIP_DEFLATED)
n = 0
for it in zin.infolist():
    d = zin.read(it.filename)
    if it.filename.endswith(('HermesEnabler2', 'HermesCompanion')):
        c = d.count(OLD)
        if c: d = d.replace(OLD, GID); n += c
    zout.writestr(it, d)
zout.close()
print(f'replaced {n} occurrences -> {GID.decode()}')
PYEOF

WINFO="$WORK/watch-info.json"
rm -f "$WINFO"
"$VENV/bin/python" "$HELPER/watch_device.py" --state-directory "$STATE" --device-info "$WINFO" 2>&1 | tail -3
WUDID=$(python3 -c "import json;print(json.load(open('$WINFO'))['udid'])")
ok "Watch UDID: $WUDID"

rm -f "$WORK/hermes-signed.ipa"
xtool_watch install "$WORK/hermes-grouped.ipa" \
  --watch-udid "$WUDID" \
  --signed-ipa-output "$WORK/hermes-signed.ipa"
ok "iPhone 侧安装完成"

# 提取并直推手表
rm -rf extract-watch && mkdir extract-watch
unzip -o -q "$WORK/hermes-signed.ipa" 'Payload/*/Watch/*.app/*' -d extract-watch
APP=$(find extract-watch -name '*.app' -type d | head -1)
[ -n "$APP" ] || die "找不到 watch .app"
say "直推手表: $APP"
"$VENV/bin/python" "$HELPER/watch_device.py" --state-directory "$STATE" --install "$APP"

echo
ok "全部完成！在手表上打开 HermesEnabler 即可。"
say "组 ID: $GID · Watch: $WUDID · 7 天后重跑本脚本续签"
