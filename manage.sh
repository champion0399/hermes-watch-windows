#!/bin/bash
# Hermes Watch Manager — renew / upgrade / status
# 复用 install.sh 已建好的环境；Apple ID session 由 xtool 持久化（当前 token 到 2027）
set -euo pipefail

RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[1;33m'; CYN='\033[0;36m'; NC='\033[0m'
say() { echo -e "${CYN}[*]${NC} $*"; }
ok()  { echo -e "${GRN}[✓]${NC} $*"; }
warn(){ echo -e "${YEL}[!]${NC} $*"; }
die() { echo -e "${RED}[✗]${NC} $*"; exit 1; }

SRC="$HOME/Developer/xtool-watch-src"
HELPER="$HOME/Developer/watch-device-helper"
STATE="$HOME/xtool-tmp/watch-device-state"
WORK="$HOME/xtool-tmp"
CONF="$WORK/hermes-watch.conf"
PATCH_PY="$WORK/patch-group.py"
DEPS="$HOME/Developer/xtool-native-deps"

export PKG_CONFIG_PATH="$DEPS/prefix/lib/pkgconfig"
export LD_LIBRARY_PATH="$DEPS/prefix/lib"

GATEWAY=$(ip route show default | awk '{print $3}')
export USBMUXD_SOCKET_ADDRESS="$GATEWAY:27015"

# 自动探测 xtool 二进制（swift 把产物放 .build/<arch>-<os>-gnu/{debug,release}/xtool）
XTOOL_BIN=""
shopt -s nullglob
for d in "$HOME/Developer"/xtool* "$HOME"/xtool*; do
  b=$(find "$d" -path '*/.build/*/xtool' -type f -executable 2>/dev/null | sort -r | head -1 || true)
  [ -n "$b" ] && XTOOL_BIN="$b" && break
done
shopt -u nullglob
[ -n "$XTOOL_BIN" ] || die "xtool 未安装，先跑 install.sh"
say "xtool: $XTOOL_BIN"

# 自动探测 pymobiledevice3 venv 和 watch helper（缺失就下载/重建）
setup_watch_env() {
  local venv=""
  for c in "$HOME/Developer/xtool-watch-venv" "$HOME/Developer/xtool-watch-device-venv"; do
    [ -x "$c/bin/python" ] && venv="$c" && break
  done
  if [ -z "$venv" ]; then
    venv="$HOME/Developer/xtool-watch-device-venv"
    say "创建 pymobiledevice3 venv: $venv"
    python3 -m venv "$venv" && "$venv/bin/pip" -q install --upgrade pip pymobiledevice3 || die "venv 创建失败"
  fi
  VENV="$venv"
  mkdir -p "$HELPER"
  for f in watch_connection.py watch_device.py; do
    [ -s "$HELPER/$f" ] || curl -sL "https://raw.githubusercontent.com/champion0399/hermes-watch-windows/main/watch-device-helper/$f" -o "$HELPER/$f" || die "下载 $f 失败"
  done
  [ -s "$HELPER/watch_device.py" ] || die "watch_device.py 不存在"
  VENV="$venv"
}
xtool_watch() { LD_LIBRARY_PATH="$LD_LIBRARY_PATH" USBMUXD_SOCKET_ADDRESS="$USBMUXD_SOCKET_ADDRESS" "$XTOOL_BIN" "$@"; }
load_conf() {
  if [ -f "$CONF" ]; then . "$CONF"; return; fi
  # 引导：手动装过的人没有 conf，从已签名的 IPA 里反推组 ID，手表 UDID 当场查
  SIGNED_IPA=$(ls -t "$WORK"/*-signed.ipa 2>/dev/null | head -1)
  [ -n "$SIGNED_IPA" ] || die "没有配置也没有已签名 IPA — 先跑 install.sh"
  GROUP_ID=$(python3 - "$SIGNED_IPA" <<'PYEOF'
import zipfile, re, sys
z=zipfile.ZipFile(sys.argv[1])
for n in z.namelist():
    if n.endswith('mobileprovision'):
        m=re.search(rb'group\.[a-zA-Z0-9.-]{1,18}', z.read(n))
        if m: print(m.group().decode()); sys.exit(0)
PYEOF
)
  [ -n "$GROUP_ID" ] || die "从 mobileprovision 里读不到组 ID"
  local f="$WORK/watch-info.json"
  "$VENV/bin/python" "$HELPER/watch_device.py" --state-directory "$STATE" --device-info "$f" >/dev/null 2>&1
  WATCH_UDID=$(python3 -c "import json;print(json.load(open('$f'))['udid'])" 2>/dev/null || true)
  APP_NAME="HermesEnabler2.app"; LAST_IPA_URL="(manual)"; GROUPED_IPA=$(ls -t "$WORK"/*grouped.ipa 2>/dev/null | head -1)
  save_conf
  echo "已自动建立配置：GROUP_ID=$GROUP_ID"
}
save_conf()   { cat > "$CONF" <<EOF
GROUP_ID="$GROUP_ID"
WATCH_UDID="$WATCH_UDID"
APP_NAME="$APP_NAME"
LAST_IPA_URL="$LAST_IPA_URL"
SIGNED_IPA="$SIGNED_IPA"
GROUPED_IPA="$GROUPED_IPA"
EOF
}

# ---------- 工具 ----------
need_watch_ipa() {
  load_conf
  [ -n "$GROUPED_IPA" ] && [ -f "$GROUPED_IPA" ] || die "没有已 patch 的 IPA，先跑 install.sh"
}
fetch_watch_udid() {
  local f="$WORK/watch-info.json"
  rm -f "$f"   # watch_device.py 用独占创建，文件已存在会 FileExistsError
  "$VENV/bin/python" "$HELPER/watch_device.py" --state-directory "$STATE" --device-info "$f" 2>&1 | tail -3
  WATCH_UDID=$(python3 -c "import json;print(json.load(open('$f'))['udid'])")
  save_conf
  echo "$WATCH_UDID"
}
extract_and_push() {
  local app=$1
  rm -rf "$WORK/extract-watch" && mkdir -p "$WORK/extract-watch"
  unzip -o -q "$SIGNED_IPA" "Payload/*/Watch/*.app/*" -d "$WORK/extract-watch"
  local wapp=$(find "$WORK/extract-watch" -name '*.app' -type d | head -1)
  [ -n "$wapp" ] || die "找不到 watch .app"
  say "直推手表: $(basename "$wapp")"
  "$VENV/bin/python" "$HELPER/watch_device.py" --state-directory "$STATE" --install "$wapp"
}

cmd_status() {
  say "=== Hermes Watch 状态 ==="
  setup_watch_env
  load_conf
  echo "Group ID:     $GROUP_ID"
  echo "Watch UDID:   $WATCH_UDID"
  echo "App:          ${APP_NAME:-?}"
  echo "Signed IPA:   ${SIGNED_IPA:-?}"
  [ -f "$SIGNED_IPA" ] && echo "签名时间:     $(stat -c '%y' "$SIGNED_IPA" | cut -d. -f1)"
  say "=== xtool Apple ID ==="
  xtool_watch auth status 2>&1 || true
  say "=== 手表连通性 ==="
  local f="$WORK/watch-info.json"
  rm -f "$f"
  if "$VENV/bin/python" "$HELPER/watch_device.py" --state-directory "$STATE" --device-info "$f" >/dev/null 2>&1; then
    ok "手表可连接（UDID $WATCH_UDID）"
  else
    warn "手表当前连不上（需 iPhone 在线 + 手表亮屏解锁）"
  fi
}

cmd_renew() {
  setup_watch_env
  need_watch_ipa
  say "=== 续签（重新签名 + 重装）==="
  say "Apple ID: 复用已存 session（2027 过期，不需要重登）"
  fetch_watch_udid >/dev/null
  rm -f "$SIGNED_IPA"
  xtool_watch install "$GROUPED_IPA" --watch-udid "$WATCH_UDID" --signed-ipa-output "$SIGNED_IPA"
  extract_and_push
  ok "续签完成，7 天有效期已重置"
}

cmd_upgrade() {
  setup_watch_env
  need_watch_ipa
  say "=== 升级到最新版 ==="
  local url
  url=$(curl -s https://api.github.com/repos/pookjw/HermesEnabler/releases/latest | grep -o 'https://[^"]*\.ipa' | head -1)
  [ -n "$url" ] || die "拿不到最新 release"
  say "Latest: $url"
  curl -L -o "$WORK/hermes-latest.ipa" "$url"
  say "patch 组 ID: $GROUP_ID"
  python3 - "$GROUP_ID" <<'PYEOF'
import zipfile, sys
GID=sys.argv[1].encode(); OLD=b'group.com.kamui.escape'
zin=zipfile.ZipFile('hermes-latest.ipa'); zout=zipfile.ZipFile('hermes-grouped.ipa','w',zipfile.ZIP_DEFLATED)
n=0
for it in zin.infolist():
    d=zin.read(it.filename)
    if it.filename.endswith(('HermesEnabler2','HermesCompanion')):
        c=d.count(OLD)
        if c: d=d.replace(OLD,GID); n+=c
    zout.writestr(it,d)
zout.close(); print(f'replaced {n}')
PYEOF
  rm -f "$SIGNED_IPA"
  xtool_watch install "$GROUPED_IPA" --watch-udid "$WATCH_UDID" --signed-ipa-output "$SIGNED_IPA"
  extract_and_push
  ok "升级完成"
}

case "${1:-help}" in
  status)  cmd_status ;;
  renew)   cmd_renew ;;
  upgrade) cmd_upgrade ;;
  *) echo "用法: manage.sh {status|renew|upgrade}"; exit 1 ;;
esac
