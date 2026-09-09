#!/bin/bash
# DeepSeek Harness 分享版 · 免密安装器
set -u
LOG="${DSH_INSTALL_LOG:-$HOME/Library/Logs/DeepSeek Harness/installer.log}"
mkdir -p "$(dirname "$LOG")"
exec 2>>"$LOG"
log() { echo "[$(date '+%F %T')] $*" >>"$LOG"; }
log "== 安装开始 (HOME=$HOME) =="
DEST_ROOT="${DSH_DEST_ROOT:-$HOME/Applications}"
mkdir -p "$DEST_ROOT"
SRC_APP="$(cd "$(dirname "$0")/../../.." && pwd)/DeepSeek Harness.app"
[ -d "$SRC_APP" ] || { log "找不到源 $SRC_APP"; exit 1; }
DEST_APP="$DEST_ROOT/DeepSeek Harness.app"
if pgrep -f "/DeepSeek Harness.app/Contents/MacOS/DeepSeek Harness" >/dev/null 2>&1; then
  pkill -f "/DeepSeek Harness.app/Contents/MacOS/DeepSeek Harness" 2>/dev/null || true
  sleep 2
fi
rm -rf "$DEST_APP" || exit 1
cp -R "$SRC_APP" "$DEST_APP" >>"$LOG" 2>&1 || { log "拷贝失败"; exit 1; }
xattr -cr "$DEST_APP" >>"$LOG" 2>&1 || true
log "拷贝完成 -> $DEST_APP"
if [ "${DSH_NO_LAUNCH:-0}" != "1" ]; then
  open "$DEST_APP" >>"$LOG" 2>&1 || log "启动失败"
fi
log "== 完成 =="
exit 0
