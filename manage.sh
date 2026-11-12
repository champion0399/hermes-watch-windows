#!/bin/bash
# Hermes Watch Manager: validated renew/upgrade/status, using the existing installation.
set -Eeuo pipefail
umask 077
ACTION=${1:-help}
case "$ACTION" in status|renew|upgrade) ;; *) printf 'Usage: manage.sh {status|renew|upgrade}\n'; exit 2 ;; esac
say() { printf '[*] %s\n' "$*"; }
ok() { printf '[✓] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }
die() { printf '[✗] %s\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "[ERROR] manage.sh line %s, exit %s: %s\n" "$LINENO" "$rc" "$BASH_COMMAND" >&2; exit "$rc"' ERR
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
WORK="$HOME/xtool-tmp"
CONF="$WORK/hermes-watch.conf"
STATE="$WORK/watch-device-state"
PREFIX="$HOME/Developer/xtool-native-deps/prefix"
ASSETS_URL='https://github.com/champion0399/hermes-watch-windows/releases/latest/download'
export PATH="$PREFIX/bin:$PATH"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export LD_LIBRARY_PATH="$PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
mkdir -p "$WORK"
command -v flock >/dev/null || die '缺少 flock，请完成首次安装环境准备'
exec 9>"$WORK/.hermes-operation.lock"
flock -n 9 || die '已有安装或管理任务正在运行，请等它结束'
SESSION_TMP=$(mktemp -d "$WORK/manage.XXXXXXXX")
trap 'rm -rf -- "$SESSION_TMP"' EXIT

download() {
  local url=$1 dest=$2
  if ! curl --fail --location --show-error --connect-timeout 20 --max-time 180 --retry 2 "$url" --output "$dest.part"; then
    rm -f -- "$dest.part"; die "下载失败: $url"
  fi
  [ -s "$dest.part" ] || die "下载内容为空: $url"
  mv -f -- "$dest.part" "$dest"
}
RUNTIME="$SCRIPT_DIR/lib/hermes_runtime.py"
if [ ! -f "$RUNTIME" ]; then
  RUNTIME="$SESSION_TMP/hermes_runtime.py"
  download "$ASSETS_URL/hermes_runtime.py" "$RUNTIME"
fi
python3 - "$RUNTIME" <<'PY'
import ast, pathlib, sys
ast.parse(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
PY
json_field() {
  python3 - "$1" "$2" "${3:-}" <<'PY'
import json, sys
value = json.load(open(sys.argv[1], encoding='utf-8'))
if sys.argv[3]: value = value[sys.argv[3]]
result = value.get(sys.argv[2], '')
if result is None: result = ''
if isinstance(result, (dict, list)) or '\n' in str(result) or '\x00' in str(result):
    raise SystemExit('Invalid JSON field')
print(result)
PY
}
load_conf() {
  if [ -f "$CONF" ]; then
    python3 "$RUNTIME" config-read "$CONF" > "$SESSION_TMP/config.json"
  else
    python3 "$RUNTIME" config-import "$WORK" > "$SESSION_TMP/config.json"
    say '已识别旧安装；配置会在本次设备安装验证成功后保存'
  fi
  GROUP_ID=$(json_field "$SESSION_TMP/config.json" GROUP_ID values)
  WATCH_UDID=$(json_field "$SESSION_TMP/config.json" WATCH_UDID values)
  APP_NAME=$(json_field "$SESSION_TMP/config.json" APP_NAME values)
  LAST_IPA_URL=$(json_field "$SESSION_TMP/config.json" LAST_IPA_URL values)
  SIGNED_IPA=$(json_field "$SESSION_TMP/config.json" SIGNED_IPA values)
  GROUPED_IPA=$(json_field "$SESSION_TMP/config.json" GROUPED_IPA values)
  UPSTREAM_TAG=$(json_field "$SESSION_TMP/config.json" UPSTREAM_TAG values)
  LAST_SUCCESS_AT=$(json_field "$SESSION_TMP/config.json" LAST_SUCCESS_AT values)
  export XTOOL_APP_GROUP_ID="$GROUP_ID"
  # Old releases sometimes left config pointing at a historical *-signed.ipa.
  local canonical="$WORK/hermes-signed.ipa"
  if [ "$SIGNED_IPA" != "$canonical" ] && [ -f "$canonical" ] && { [ -z "$SIGNED_IPA" ] || [ ! -f "$SIGNED_IPA" ] || [ "$canonical" -nt "$SIGNED_IPA" ]; }; then
    python3 "$RUNTIME" verify-grouped "$canonical" "$GROUP_ID" >/dev/null
    python3 "$RUNTIME" profile "$canonical" > "$SESSION_TMP/canonical-profile.json"
    python3 - "$SESSION_TMP/canonical-profile.json" "$GROUP_ID" <<'PY'
import json,sys
if sys.argv[2] not in json.load(open(sys.argv[1]))['groups']: raise SystemExit('最新签名缓存的 App Group 与配置不匹配')
PY
    SIGNED_IPA="$canonical"
    say '已识别较新的标准签名缓存，避免续签历史版本'
  fi
}
find_xtool() {
  local root candidate
  if [ -n "${XTOOL_BIN:-}" ]; then
    [ -x "$XTOOL_BIN" ] || die "指定的 xtool 不可执行: $XTOOL_BIN"
  else
    XTOOL_BIN=''
    shopt -s nullglob
    for root in "$HOME/Developer/xtool-watch-src" "$HOME/Developer/xtool-watch-fix" "$HOME/Developer"/xtool* "$HOME"/xtool*; do
      for candidate in "$root/.build/debug/xtool" "$root/.build/release/xtool" "$root"/.build/*/debug/xtool "$root"/.build/*/release/xtool; do
        if [ -x "$candidate" ]; then XTOOL_BIN="$candidate"; break 2; fi
      done
    done
    shopt -u nullglob
  fi
  [ -n "$XTOOL_BIN" ] || die '找不到支持手表的 xtool，请先完成首次安装'
  "$XTOOL_BIN" install --help > "$SESSION_TMP/xtool-help.txt"
  grep -q -- '--watch-udid' "$SESSION_TMP/xtool-help.txt" && grep -q -- '--signed-ipa-output' "$SESSION_TMP/xtool-help.txt" || die '找到的 xtool 缺少手表签名参数，请更新安装环境'
  say "xtool: $XTOOL_BIN"
}
xtool_watch() { "$XTOOL_BIN" "$@"; }
setup_watch_env() {
  local candidate source f
  VENV=''
  for candidate in "$HOME/Developer/xtool-watch-venv" "$HOME/Developer/xtool-watch-device-venv"; do
    if [ -x "$candidate/bin/python" ] && "$candidate/bin/python" -c 'import pymobiledevice3' >/dev/null 2>&1; then VENV="$candidate"; break; fi
  done
  if [ -z "$VENV" ]; then
    [ "$ACTION" != status ] || die '缺少 pymobiledevice3 虚拟环境，请完成首次安装'
    VENV="$HOME/Developer/xtool-watch-device-venv"
    python3 -m venv "$VENV"
    "$VENV/bin/python" -m pip -q install 'pymobiledevice3==11.31.0'
  fi
  HELPER="$SESSION_TMP/helpers"
  mkdir -p "$HELPER"
  for f in watch_connection.py watch_device.py; do
    source="$SCRIPT_DIR/watch-device-helper/$f"
    if [ -s "$source" ]; then
      cp -- "$source" "$HELPER/$f"
    else
      download "$ASSETS_URL/$f" "$HELPER/$f"
    fi
  done
  python3 - "$HELPER" <<'PY'
import ast, pathlib, sys
for p in pathlib.Path(sys.argv[1]).glob('*.py'): ast.parse(p.read_text(encoding='utf-8'))
PY
}
connect_watch() {
  local gateway actual
  gateway=$(ip -4 route show default | awk 'NR==1 {print $3}')
  if [ -n "$gateway" ] && timeout 4 bash -c 'echo > "/dev/tcp/$1/27015"' _ "$gateway" 2>/dev/null; then
    export USBMUXD_SOCKET_ADDRESS="$gateway:27015"
  elif timeout 4 bash -c 'echo > /dev/tcp/127.0.0.1/27015' 2>/dev/null; then
    export USBMUXD_SOCKET_ADDRESS='127.0.0.1:27015'
  else
    die 'WSL 连不上 Windows usbmux:27015，请在图形界面检查 USB 桥接与 Apple 服务'
  fi
  "$VENV/bin/python" "$HELPER/watch_device.py" --state-directory "$STATE" --device-info "$SESSION_TMP/watch-info.json"
  actual=$(python3 - "$SESSION_TMP/watch-info.json" <<'PY'
import json,re,sys
value=json.load(open(sys.argv[1]))['udid']
if not isinstance(value,str) or not re.fullmatch(r'[A-Za-z0-9-]+',value): raise SystemExit('Invalid Watch UDID')
print(value)
PY
)
  if [ -n "$WATCH_UDID" ] && [ "$WATCH_UDID" != "$actual" ]; then
    die '连接的手表与配置中的手表不同，已停止，避免安装到另一台设备'
  fi
  WATCH_UDID="$actual"
}
ensure_auth() {
  local auth
  auth=$(xtool_watch auth status) || auth=''
  if ! grep -q '^Logged in\.' <<< "$auth"; then
    say 'Apple ID 会话需要重新登录，接下来可能要求输入密码和验证码'
    if [ -t 0 ]; then
      xtool_watch auth login
    elif { exec 3</dev/tty; } 2>/dev/null; then
      xtool_watch auth login <&3
    else
      die 'Apple ID 会话已失效，请从图形界面交互终端重新登录'
    fi
    auth=$(xtool_watch auth status)
    grep -q '^Logged in\.' <<< "$auth" || die 'Apple ID 重新登录验证失败'
  fi
}
commit_success() {
  # Only move new artifacts into the durable cache after the Watch lookup receipt was validated.
  if [ "$ACTION" = upgrade ]; then
    mv -f -- "$SESSION_TMP/upstream.ipa" "$WORK/hermes-latest.ipa"
    mv -f -- "$SESSION_TMP/grouped.ipa" "$WORK/hermes-grouped.ipa"
    mv -f -- "$SESSION_TMP/release.json" "$WORK/hermes-release.json"
    GROUPED_IPA="$WORK/hermes-grouped.ipa"
  fi
  mv -f -- "$SESSION_TMP/signed.ipa" "$WORK/hermes-signed.ipa"
  SIGNED_IPA="$WORK/hermes-signed.ipa"
  mv -f -- "$SESSION_TMP/receipt.json" "$WORK/last-install-receipt.json"
  mv -f -- "$SESSION_TMP/profile.json" "$WORK/last-signing-profile.json"
  LAST_SUCCESS_AT=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
  python3 - "$CONF" "$GROUP_ID" "$WATCH_UDID" "$APP_NAME" "$LAST_IPA_URL" "$SIGNED_IPA" "$GROUPED_IPA" "$UPSTREAM_TAG" "$LAST_SUCCESS_AT" <<'PY'
import os, pathlib, shlex, sys
keys=['GROUP_ID','WATCH_UDID','APP_NAME','LAST_IPA_URL','SIGNED_IPA','GROUPED_IPA','UPSTREAM_TAG','LAST_SUCCESS_AT']
p=pathlib.Path(sys.argv[1]); temp=p.with_suffix('.conf.new')
with temp.open('w',encoding='utf-8') as f:
    for key,value in zip(keys,sys.argv[2:]): f.write(key+'='+shlex.quote(value)+'\n')
os.chmod(temp,0o600); os.replace(temp,p)
PY
}
install_and_verify() {
  local source=$1 app expires
  python3 "$RUNTIME" verify-grouped "$source" "$GROUP_ID"
  xtool_watch install "$source" --watch-udid "$WATCH_UDID" --signed-ipa-output "$SESSION_TMP/signed.ipa"
  [ -s "$SESSION_TMP/signed.ipa" ] || die 'xtool 未生成已签名 IPA，未执行直推'
  python3 "$RUNTIME" verify-signed "$SESSION_TMP/signed.ipa" "$GROUP_ID" "$WATCH_UDID" > "$SESSION_TMP/profile.json"
  if [ "$ACTION" = renew ] && [ -n "$SIGNED_IPA" ] && [ -f "$SIGNED_IPA" ]; then
    # A successful re-install with the same cached expiry is not an extension of validity.
    python3 "$RUNTIME" profile "$SIGNED_IPA" > "$SESSION_TMP/old-profile.json"
    python3 - "$SESSION_TMP/old-profile.json" "$SESSION_TMP/profile.json" <<'PY'
import datetime,json,sys
old=json.load(open(sys.argv[1])).get('expires'); new=json.load(open(sys.argv[2]))['expires']
if old and datetime.datetime.fromisoformat(new.replace('Z','+00:00')).replace(tzinfo=datetime.timezone.utc) <= datetime.datetime.fromisoformat(old.replace('Z','+00:00')).replace(tzinfo=datetime.timezone.utc):
    raise SystemExit('描述文件到期时间没有延长；已停止手表重装，请检查 Apple 描述文件刷新状态')
PY
  fi
  app=$(python3 "$RUNTIME" extract-watch "$SESSION_TMP/signed.ipa" "$SESSION_TMP/extract-watch")
  APP_NAME=$(basename -- "$app")
  say "直推手表: $APP_NAME"
  "$VENV/bin/python" "$HELPER/watch_device.py" --state-directory "$STATE" --install "$app" --receipt "$SESSION_TMP/receipt.json"
  python3 "$RUNTIME" info "$SESSION_TMP/signed.ipa" > "$SESSION_TMP/app-info.json"
  python3 - "$SESSION_TMP/receipt.json" "$SESSION_TMP/app-info.json" "$WATCH_UDID" <<'PY'
import json,sys
r=json.load(open(sys.argv[1])); i=json.load(open(sys.argv[2]))
if r.get('installed_verified') is not True or r.get('udid')!=sys.argv[3] or any(r.get(k)!=i.get(k) for k in ('bundle_id','version','build')):
    raise SystemExit('手表安装收据与签名包不一致，未记录成功')
PY
  expires=$(json_field "$SESSION_TMP/profile.json" expires)
  commit_success
  if [ "$ACTION" = renew ]; then ok "续签并验证完成；描述文件到期时间 (UTC): $expires";
  else ok "升级并验证完成；上游版本: $UPSTREAM_TAG；描述文件到期时间 (UTC): $expires"; fi
}
cmd_status() {
  say '=== Hermes Watch 状态 ==='
  printf 'App Group: %s\n历史记录版本: %s\n上次成功安装 (UTC): %s\n' "$GROUP_ID" "${UPSTREAM_TAG:-未知（旧安装无版本记录）}" "${LAST_SUCCESS_AT:-未知}"
  if [ -n "$SIGNED_IPA" ] && [ -f "$SIGNED_IPA" ]; then
    python3 "$RUNTIME" profile "$SIGNED_IPA" > "$SESSION_TMP/profile.json"
    printf '本地签名包到期时间 (UTC): %s\n' "$(json_field "$SESSION_TMP/profile.json" expires)"
    python3 "$RUNTIME" info "$SIGNED_IPA" > "$SESSION_TMP/app-info.json"
  else
    die '本地签名包缺失，请完成首次安装或升级后再验证状态'
  fi
  setup_watch_env
  connect_watch
  local bundle
  bundle=$(json_field "$SESSION_TMP/app-info.json" bundle_id)
  "$VENV/bin/python" "$HELPER/watch_device.py" --state-directory "$STATE" --inspect-bundle "$bundle" --inspect-output "$SESSION_TMP/installed.json"
  python3 - "$SESSION_TMP/installed.json" "$WATCH_UDID" "$bundle" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))
if r.get('found') is not True or r.get('udid')!=sys.argv[2] or r.get('bundle_id')!=sys.argv[3]: raise SystemExit('手表未查到与配置匹配的应用')
print('手表应用已查到；设备上报版本:',r.get('version'),'构建:',r.get('build'))
print('提示：设备上报版本可能固定为1.0；历史记录版本来自成功安装的上游发布包。')
PY
  ok '手表连接与应用查询完成'
}

load_conf
find_xtool
case "$ACTION" in
  status) cmd_status ;;
  renew)
    say '=== 续签 ==='
    setup_watch_env; connect_watch; ensure_auth
    SOURCE_IPA="$SIGNED_IPA"
    if [ -z "$SOURCE_IPA" ] || [ ! -f "$SOURCE_IPA" ]; then
      SOURCE_IPA="$GROUPED_IPA"
      [ -n "$SOURCE_IPA" ] && [ -f "$SOURCE_IPA" ] || die '续签输入 IPA 缺失，请先升级或完成首次安装'
      say '签名缓存缺失，将重新签署已保存的 grouped IPA'
    else
      say '续签保留当前签名缓存中的应用版本'
    fi
    install_and_verify "$SOURCE_IPA"
    ;;
  upgrade)
    say '=== 升级到原作者最新发布版本 ==='
    setup_watch_env; connect_watch; ensure_auth
    python3 "$RUNTIME" latest "$SESSION_TMP/upstream.ipa" > "$SESSION_TMP/release.json"
    LAST_IPA_URL=$(json_field "$SESSION_TMP/release.json" url)
    UPSTREAM_TAG=$(json_field "$SESSION_TMP/release.json" tag)
    [ -n "$UPSTREAM_TAG" ] && [ -n "$LAST_IPA_URL" ] || die '发布元数据缺失'
    say "上游版本: $UPSTREAM_TAG"
    python3 "$RUNTIME" patch "$SESSION_TMP/upstream.ipa" "$SESSION_TMP/grouped.ipa" "$GROUP_ID"
    install_and_verify "$SESSION_TMP/grouped.ipa"
    ;;
esac
