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
VENV="$HOME/Developer/xtool-watch-venv"
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

# 自动探测 xtool 二进制（新装是 xtool-watch-src，手动装过的是 xtool-watch-fix 或任意名字）
XTOOL_BIN=""
for d in "$HOME/Developer"/xtool*; do
  for cfg in release debug; do
    b="$d/.build/$cfg/xtool"
    [ -x "$b" ] && XTOOL_BIN="$b" && break 2
  done
done
[ -n "$XTOOL_BIN" ] || die "xtool 未安装，先跑 install.sh"

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
  load_conf
  echo "Group ID:     $GROUP_ID"
  echo "Watch UDID:   $WATCH_UDID"
  echo "App:          ${APP_NAME:-?}"
  echo "Signed IPA:   ${SIGNED_IPA:-?}"
  [ -f "$SIGNED_IPA" ] && echo "签名时间:     $(stat -c '%y' "$SIGNED_IPA" | cut -d. -f1)"
  say "=== xtool Apple ID ==="
  xtool_watch auth status 2>&1 || true
  say "=== 已装应用 ==="
  xtool_watch list --udid "$WATCH_UDID" 2>/dev/null | head -10 || warn "无法枚举手表应用"
}

cmd_renew() {
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
