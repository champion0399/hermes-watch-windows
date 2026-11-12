#!/bin/bash
# HermesEnabler → Apple Watch · 一键安装（Windows + Ubuntu 24.04 WSL x86_64）
# 本地运行 ./install.sh 或 curl -fsSL <release>/install.sh | bash
set -Eeuo pipefail

RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[1;33m'; CYN='\033[0;36m'; NC='\033[0m'
say()  { printf '%b\n' "${CYN}[*]${NC} $*"; }
ok()   { printf '%b\n' "${GRN}[✓]${NC} $*"; }
warn() { printf '%b\n' "${YEL}[!]${NC} $*" >&2; }
die()  { printf '%b\n' "${RED}[✗]${NC} $*" >&2; exit 1; }
ask()  { printf '%b ' "${YEL}[?]${NC} $*" >&2; }
trap 'status=$?; printf "[ERROR] install.sh line %s, exit %s: %s\n" "$LINENO" "$status" "$BASH_COMMAND" >&2; exit "$status"' ERR

# Keep the script pipe on stdin intact: only interactive commands read fd 3.
if [ -t 0 ]; then
  exec 3<&0
elif { exec 3</dev/tty; } 2>/dev/null; then
  :
else
  die "请在有交互终端的 WSL 窗口运行（Apple ID 登录和开发者模式需要输入）"
fi
[ "$(uname -s)" = Linux ] || die "请在 Ubuntu 24.04 WSL 内运行此脚本"
[ "$(uname -m)" = x86_64 ] || die "当前 Swift 下载仅支持 x86_64"
[ -r /etc/os-release ] || die "缺少 /etc/os-release"
# shellcheck disable=SC1091
. /etc/os-release
[ "${ID:-}" = ubuntu ] && [ "${VERSION_ID:-}" = 24.04 ] || die "需要 Ubuntu 24.04（当前 ${PRETTY_NAME:-unknown}）"
grep -qi microsoft /proc/sys/kernel/osrelease || die "需要 Windows WSL 环境及 Windows usbmuxd 转发"

DEPS="$HOME/Developer/xtool-native-deps"
PREFIX="$DEPS/prefix"
SRC="$HOME/Developer/xtool-watch-src"
VENV="$HOME/Developer/xtool-watch-venv"
HELPER="$HOME/Developer/watch-device-helper"
STATE="$HOME/xtool-tmp/watch-device-state"
WORK="$HOME/xtool-tmp"
HELPER_URL="https://github.com/champion0399/hermes-watch-windows/releases/latest/download"
PATCH_URL="$HELPER_URL/xtool-watch-1.24.0.patch"
SCRIPT_DIR=''
if [ -f "${BASH_SOURCE[0]:-}" ]; then
  SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
fi
export PATH="$PREFIX/bin:/opt/swift-6.4.1/usr/bin:$PATH"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export LD_LIBRARY_PATH="$PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
mkdir -p "$WORK"
command -v flock >/dev/null || die '缺少 flock，请检查 Ubuntu 基础工具'
exec 9>"$WORK/.hermes-operation.lock"
flock -n 9 || die '已有安装或管理任务正在运行，请等它结束'
SESSION_TMP=$(mktemp -d "$WORK/install.XXXXXXXX")
trap 'rm -rf -- "$SESSION_TMP"' EXIT

# Download atomically; HTTP failures retain neither an HTML error nor a partial file.
# Optional expected SHA-256 is used when release metadata supplies a digest.
download() {
  local url=$1 dest=$2 expected=${3:-} actual
  if ! curl --fail --location --show-error --retry 3 --connect-timeout 20 \
      --output "$dest.part" "$url"; then
    rm -f -- "$dest.part"
    die "下载失败: $url"
  fi
  [ -s "$dest.part" ] || die "下载内容为空: $url"
  actual=$(sha256sum "$dest.part"); actual=${actual%% *}
  if [ -n "$expected" ] && [ "$actual" != "${expected#sha256:}" ]; then
    rm -f -- "$dest.part"
    die "SHA-256 不匹配: $url (expected $expected, got $actual)"
  fi
  say "SHA-256: $actual ($(basename -- "$dest"))"
  mv -f -- "$dest.part" "$dest"
}

GATEWAY=$(ip -4 route show default | awk 'NR == 1 {print $3}')
say "WSL gateway: ${GATEWAY:-none (trying localhost)}"
say "工作目录: $WORK"
say "0/8 检查 usbmuxd 连通性（iPhone 需解锁亮屏）"
if [ -n "$GATEWAY" ] && timeout 4 bash -c 'echo > "/dev/tcp/$1/27015"' _ "$GATEWAY" 2>/dev/null; then
  export USBMUXD_SOCKET_ADDRESS="$GATEWAY:27015"
elif timeout 4 bash -c 'echo > /dev/tcp/127.0.0.1/27015' 2>/dev/null; then
  # Mirrored WSL networking can reach the Windows localhost listener directly.
  export USBMUXD_SOCKET_ADDRESS="127.0.0.1:27015"
else
  die "WSL 网关和 localhost 均连不上 usbmuxd:27015 — 请用 Windows 安装器准备 USB 转发，并确认 Apple Devices 与 iPhone 信任状态"
fi
ok "usbmuxd reachable: $USBMUXD_SOCKET_ADDRESS"

say "1/8 安装系统依赖（需要 sudo）"
sudo apt-get update -qq
sudo apt-get install -y -qq build-essential git curl pkg-config autoconf automake libtool \
  libssl-dev unzip zip python3 python3-venv python3-pip jq binutils gnupg2 \
  libc6-dev libcurl4-openssl-dev libedit2 libgcc-13-dev libpython3-dev \
  libstdc++-13-dev libxml2-dev libz3-dev tzdata zlib1g-dev libncurses-dev libsqlite3-dev
ok "apt deps"

# PATH was set before probing, so an existing /opt installation is reused.
if ! swift --version 2>/dev/null | grep -q 'Swift version 6\.4\.1'; then
  say "2/8 安装 Swift 6.4.1（验证官方签名）"
  SWIFT_URL="https://download.swift.org/swift-6.4.1-release/ubuntu2404/swift-6.4.1-RELEASE/swift-6.4.1-RELEASE-ubuntu24.04.tar.gz"
  download "$SWIFT_URL" "$SESSION_TMP/swift.tgz"
  download "$SWIFT_URL.sig" "$SESSION_TMP/swift.tgz.sig"
  download "https://www.swift.org/keys/all-keys.asc" "$SESSION_TMP/swift-keys.asc"
  mkdir -m 700 "$SESSION_TMP/gnupg"
  gpg --batch --homedir "$SESSION_TMP/gnupg" --import "$SESSION_TMP/swift-keys.asc"
  gpg --batch --homedir "$SESSION_TMP/gnupg" --verify "$SESSION_TMP/swift.tgz.sig" "$SESSION_TMP/swift.tgz"
  tar -tzf "$SESSION_TMP/swift.tgz" >/dev/null
  sudo mkdir -p /opt/swift-6.4.1
  sudo tar -xzf "$SESSION_TMP/swift.tgz" -C /opt/swift-6.4.1 --strip-components=1
else
  say "2/8 Swift 6.4.1 已装，跳过"
fi
swift --version

# Rebuild installations made by the old script, which disabled every project's tools.
if [ ! -f "$DEPS/.deps-tools-v2" ] || [ ! -x "$PREFIX/bin/idevice_id" ] || [ ! -x "$PREFIX/bin/ideviceinfo" ]; then
  say "3/8 编译 libimobiledevice 1.4 全家桶（约 10 分钟）"
  mkdir -p "$DEPS/src" "$PREFIX"
  build_dep() (
    local project=$1 version=$2
    local src="$DEPS/src/$project"
    [ -d "$src/.git" ] || git clone --depth 1 --branch "$version" "https://github.com/libimobiledevice/$project.git" "$src"
    cd "$src"
    # libplist's tools are needed by native dependencies; idevice_id comes from libimobiledevice.
    ./autogen.sh --prefix="$PREFIX" --without-cython
    make -j4
    make install
  )
  build_dep libplist 2.6.0
  build_dep libimobiledevice-glue 1.3.1
  build_dep libusbmuxd 2.1.0
  build_dep libtatsu 1.0.4
  build_dep libimobiledevice 1.4.0
  [ -x "$PREFIX/bin/idevice_id" ] && [ -x "$PREFIX/bin/ideviceinfo" ] || die "原生工具构建失败"
  touch "$DEPS/.deps-tools-v2"
else
  say "3/8 libimobiledevice 已装，跳过"
fi
PHONE_IDS=$(idevice_id -l) || die "读取 iPhone 列表失败"
PHONE_UDID=${PHONE_IDS%%$'\n'*}
[ -n "$PHONE_UDID" ] || die "看不到 iPhone — 解锁亮屏并确认信任后重试"
[ "$PHONE_IDS" = "$PHONE_UDID" ] || die "检测到多台 iPhone，请只连接目标 iPhone"
ok "iPhone: $PHONE_UDID"
[ "$(ideviceinfo -u "$PHONE_UDID" -k PasswordProtected 2>/dev/null)" = false ] || warn "请确认 iPhone 已解锁"

say "4/8 准备 xtool 1.24.0 与 Watch 补丁"
if [ ! -e "$SRC" ]; then
  git clone --depth 1 --branch 1.24.0 https://github.com/xtool-org/xtool.git "$SRC"
fi
[ -d "$SRC/.git" ] || die "$SRC 已存在但不是 git 源码目录；请手动选择保留或移动后重跑"
cd "$SRC"
[ "$(git describe --tags --exact-match HEAD 2>/dev/null)" = 1.24.0 ] || die "已有 $SRC 不是 xtool 1.24.0；保留目录供检查"
PATCH="$SESSION_TMP/xtool-watch.patch"
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/patches/xtool-watch-1.24.0.patch" ]; then
  cp -- "$SCRIPT_DIR/patches/xtool-watch-1.24.0.patch" "$PATCH"
else
  download "$PATCH_URL" "$PATCH"
fi
grep -q 'XTOOL_APP_GROUP_ID' "$PATCH" || die "Watch 补丁版本过旧：缺少 XTOOL_APP_GROUP_ID，请更新发行包"
if git apply --reverse --check "$PATCH" 2>/dev/null; then
  say "   当前补丁已应用"
elif git apply --check "$PATCH"; then
  git apply "$PATCH"
else
  die "补丁与现有源码不匹配；已保留 $SRC，请备份并移动旧目录后重跑"
fi
# Record the actual patch digest: a changed patch requires an incremental rebuild.
PATCH_HASH=$(sha256sum "$PATCH"); PATCH_HASH=${PATCH_HASH%% *}
BUILD_HASH=''
[ ! -f "$SRC/.watch-build-sha256" ] || BUILD_HASH=$(<"$SRC/.watch-build-sha256")
if [ "$BUILD_HASH" != "$PATCH_HASH" ] || { [ ! -x "$SRC/.build/release/xtool" ] && [ ! -x "$SRC/.build/debug/xtool" ]; }; then
  say "   编译 xtool（首次约 15-25 分钟）"
  swift build --build-system native --pkg-config-path "$PREFIX/lib/pkgconfig" -j 4 \
    -Xcc -I"$PREFIX/include" -Xlinker -L"$PREFIX/lib" \
    -Xlinker -rpath -Xlinker "$PREFIX/lib" --product xtool
  # swift build defaults to debug; discard an older release binary as a candidate, not as a file.
  printf '%s\n' debug > "$SRC/.watch-build-configuration"
  printf '%s\n' "$PATCH_HASH" > "$SRC/.watch-build-sha256"
fi
XTOOL_BIN="$SRC/.build/debug/xtool"
if [ -f "$SRC/.watch-build-configuration" ] && [ "$(<"$SRC/.watch-build-configuration")" = release ]; then
  XTOOL_BIN="$SRC/.build/release/xtool"
fi
[ -x "$XTOOL_BIN" ] || die "找不到已编译的 xtool: $XTOOL_BIN"
xtool_watch() { "$XTOOL_BIN" "$@"; }
ok "xtool built: $XTOOL_BIN"

say "5/8 准备 pymobiledevice3 与手表工具"
[ -x "$VENV/bin/python" ] || python3 -m venv "$VENV"
"$VENV/bin/python" -m pip -q install 'pymobiledevice3==11.31.0'
mkdir -p "$HELPER" "$STATE"
for helper in watch_connection.py watch_device.py; do
  if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/watch-device-helper/$helper" ]; then
    cp -- "$SCRIPT_DIR/watch-device-helper/$helper" "$HELPER/$helper"
  else
    download "$HELPER_URL/$helper" "$HELPER/$helper"
  fi
done
python3 - "$HELPER" <<'PY'
import ast, pathlib, sys
for name in ('watch_connection.py', 'watch_device.py'):
    path = pathlib.Path(sys.argv[1]) / name
    ast.parse(path.read_text(encoding='utf-8'), filename=str(path))
PY
RUNTIME="$SCRIPT_DIR/lib/hermes_runtime.py"
if [ -z "$SCRIPT_DIR" ] || [ ! -f "$RUNTIME" ]; then
  RUNTIME="$WORK/hermes_runtime.py"
  download "$HELPER_URL/hermes_runtime.py" "$RUNTIME"
fi
python3 - "$RUNTIME" <<'PY'
import ast, pathlib, sys
path = pathlib.Path(sys.argv[1])
ast.parse(path.read_text(encoding='utf-8'), filename=str(path))
PY
ok "watch helper ready"

say "6/8 揭示 iPhone 与手表的开发者模式开关"
"$VENV/bin/python" -m pymobiledevice3 amfi reveal-developer-mode --udid "$PHONE_UDID" <&3
"$VENV/bin/python" "$HELPER/watch_device.py" --state-directory "$STATE" --pair --reveal-developer-mode <&3
warn "请在手表与 iPhone 的 设置→隐私与安全性→开发者模式 打开开关并重启确认"
ask "开发者模式都已开启并重启确认？(y/N)"
read -r yn <&3 || die "终端输入结束"
[[ "$yn" =~ ^[Yy]$ ]] || die "先开开发者模式再重跑"

say "7/8 Apple ID 登录与 App Group"
if ! xtool_watch auth status | grep -q '^Logged in\.'; then
  say "登录 Apple ID（会触发 2FA）"
  xtool_watch auth login <&3
fi
xtool_watch auth status | grep -q '^Logged in\.' || die "Apple ID 登录状态验证失败"
ok "Apple ID signed in"
# Persist a random 16-hex suffix: group. (6 ASCII bytes) + suffix (16) = 22.
DEFAULT_GID=${XTOOL_APP_GROUP_ID:-}
if [ -z "$DEFAULT_GID" ] && [ -f "$WORK/app-group-id" ]; then
  DEFAULT_GID=$(<"$WORK/app-group-id")
fi
if [ -z "$DEFAULT_GID" ]; then
  DEFAULT_GID=$(python3 -c 'import secrets; print("group." + secrets.token_hex(8))')
fi
ask "输入 App Group ID（22 个 ASCII 字符，group. 开头；回车用 $DEFAULT_GID）:"
read -r GID <&3 || die "终端输入结束"
GID=${GID:-$DEFAULT_GID}
python3 - "$GID" <<'PY'
import re, sys
group = sys.argv[1]
if not re.fullmatch(r'group\.[A-Za-z0-9.-]{16}', group, flags=re.ASCII):
    raise SystemExit('App Group ID 必须为 22 个 ASCII 字符，group. 开头，后接字母、数字、点或连字符')
PY
export XTOOL_APP_GROUP_ID="$GID"
printf '%s\n' "$GID" > "$WORK/app-group-id"
ok "Group ID: $GID"

say "8/8 下载最新 HermesEnabler、patch 组 ID、签名并安装"
# The runtime validates release metadata/digest and IPA structure, and fails on zero replacements.
python3 "$RUNTIME" latest "$WORK/hermes-latest.ipa" > "$WORK/hermes-release.json"
URL=$(python3 - "$WORK/hermes-release.json" <<'PY'
import json, sys
value = json.load(open(sys.argv[1], encoding='utf-8'))['url']
if not isinstance(value, str) or not value.startswith('https://') or any(c in value for c in '\r\n"'):
    raise SystemExit('Invalid release asset URL')
print(value)
PY
)
python3 "$RUNTIME" patch "$WORK/hermes-latest.ipa" "$WORK/hermes-grouped.ipa" "$GID"
WINFO="$SESSION_TMP/watch-info.json"
"$VENV/bin/python" "$HELPER/watch_device.py" --state-directory "$STATE" --device-info "$WINFO" <&3
WUDID=$(python3 - "$WINFO" <<'PY'
import json, re, sys
value = json.load(open(sys.argv[1], encoding='utf-8'))['udid']
if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z0-9-]+', value):
    raise SystemExit('Invalid Watch UDID')
print(value)
PY
)
ok "Watch UDID: $WUDID"
rm -f -- "$WORK/hermes-signed.ipa"
xtool_watch install "$WORK/hermes-grouped.ipa" --watch-udid "$WUDID" \
  --signed-ipa-output "$WORK/hermes-signed.ipa" <&3
[ -s "$WORK/hermes-signed.ipa" ] || die "xtool 没有生成已签名 IPA"
ok "iPhone 侧安装完成"
APP=$(python3 "$RUNTIME" extract-watch "$WORK/hermes-signed.ipa" "$SESSION_TMP/extract-watch")
[ -d "$APP" ] && [[ "$APP" = /* ]] || die "找不到唯一 watch .app 绝对路径"
say "直推手表: $APP"
"$VENV/bin/python" "$HELPER/watch_device.py" --state-directory "$STATE" --install "$APP" <&3

# Preserve the existing config contract; %q prevents shell expansion if sourced later.
{
  printf 'GROUP_ID=%q\n' "$GID"
  printf 'WATCH_UDID=%q\n' "$WUDID"
  printf 'APP_NAME=%q\n' "$(basename -- "$APP")"
  printf 'LAST_IPA_URL=%q\n' "$URL"
  printf 'SIGNED_IPA=%q\n' "$WORK/hermes-signed.ipa"
  printf 'GROUPED_IPA=%q\n' "$WORK/hermes-grouped.ipa"
  printf 'UPSTREAM_TAG=%q\n' "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["tag"])' "$WORK/hermes-release.json")"
  printf 'LAST_SUCCESS_AT=%q\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
} > "$WORK/hermes-watch.conf"
ok "全部完成！在手表上打开 HermesEnabler 即可。"
say "组 ID: $GID · Watch: $WUDID"
