#!/bin/bash
# =============================================================================
# sandbox-test-dmg.sh — 场景 C：直接拿**真实 DMG** 走一遍完整用户流程
#
# 场景 A/B 用的是「本地 app 目录」，本脚本则验证最终交付物本身：
#   挂载 DMG → 检查卷内结构 → 从**只读卷**上运行安装器装到沙盒 HOME
#   → 启动并验证 app 自己完成鉴权 → 卸载 → 卷内文件未被改动
#
# 用法：./sandbox-test-dmg.sh "<DeepSeekHarness-x.y.z.dmg>" [序号]
# =============================================================================
set -uo pipefail

DMG="${1:?用法: $0 <DeepSeekHarness-x.y.z.dmg> [序号]}"
IDX="${2:-1}"
MNT="/tmp/dsh-dmg-mnt-$IDX"
SANDBOX="/tmp/dsh-sandbox-dmg-$IDX"
SB_HOME="$SANDBOX/home"
SB_APP="$SB_HOME/Applications/DeepSeek Harness.app"
LOG="$SB_HOME/Library/Logs/DeepSeek Harness"
PORT=$((39200 + IDX))

PASS=0; FAIL=0
ok()   { echo "  ✓ $*"; PASS=$((PASS + 1)); }
bad()  { echo "  ✗ $*"; FAIL=$((FAIL + 1)); }
info() { echo "    $*"; }

APP_PID=""
cleanup() {
  [ -n "$APP_PID" ] && kill "$APP_PID" 2>/dev/null
  sleep 1
  local pids; pids="$(lsof -ti "tcp:$PORT" 2>/dev/null)"
  [ -n "$pids" ] && kill $pids 2>/dev/null
  hdiutil detach "$MNT" >/dev/null 2>&1
  return 0
}
trap cleanup EXIT

echo "════════ 沙盒场景 C：真实 DMG 端到端（$(basename "$DMG")）════════"
[ -f "$DMG" ] || { bad "找不到 DMG：$DMG"; exit 1; }

# ---- 1. 挂载 ---------------------------------------------------------------
hdiutil detach "$MNT" >/dev/null 2>&1
rm -rf "$SANDBOX"; mkdir -p "$SB_HOME" "$MNT"
if hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MNT" >"$SANDBOX/attach.log" 2>&1; then
  ok "DMG 挂载成功（只读）"
else
  bad "DMG 挂载失败"; cat "$SANDBOX/attach.log" | sed 's/^/      /'; exit 1
fi

# ---- 2. 卷内结构 -----------------------------------------------------------
if [ -d "$MNT/DeepSeek Harness.app" ]; then
  V="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
       "$MNT/DeepSeek Harness.app/Contents/Info.plist" 2>/dev/null)"
  ok "卷内包含 DeepSeek Harness.app（v${V}）"
  [ "$V" = "0.3.0" ] && ok "版本号符合预期（0.3.0）" || bad "版本号不是 0.3.0（实际 ${V}）"
else
  bad "卷内缺少 DeepSeek Harness.app"
fi
if [ -x "$MNT/安装 DeepSeek Harness.app/Contents/MacOS/installer" ]; then
  ok "卷内包含可执行的安装器"
else
  bad "卷内缺少安装器"
fi
NESTED="$(find "$MNT/DeepSeek Harness.app" -maxdepth 4 -name "profile-seed-web" -type d 2>/dev/null | wc -l | tr -d ' ')"
[ "$NESTED" = "1" ] && ok "种子目录无嵌套重复" || bad "种子目录数量异常（${NESTED}）"

# ---- 3. 从只读卷运行安装器 -------------------------------------------------
echo "[安装] 从只读卷运行安装器 → 沙盒 HOME"
if HOME="$SB_HOME" DSH_DEST_ROOT="$SB_HOME/Applications" DSH_NO_LAUNCH=1 \
     bash "$MNT/安装 DeepSeek Harness.app/Contents/MacOS/installer" >"$SANDBOX/install.log" 2>&1; then
  ok "安装器执行成功"
else
  bad "安装器执行失败"; tail -8 "$SANDBOX/install.log" | sed 's/^/      /'
fi
if [ -d "$SB_APP" ]; then
  ok "已装到沙盒：$SB_APP"
  IV="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
        "$SB_APP/Contents/Info.plist" 2>/dev/null)"
  [ "$IV" = "0.3.0" ] && ok "装出来的版本为 0.3.0" || bad "装出来的版本为 ${IV}"
else
  bad "安装器未产出 app"; exit 1
fi

# ---- 4. 启动并验证 app 自己完成鉴权 ----------------------------------------
echo "[启动] 全新 HOME 首启"
HOME="$SB_HOME" DSH_HOME="$SB_HOME/.dsh" DSH_PORT="$PORT" \
DSH_NO_FULLSCREEN=1 DSH_LOG_DIR="$LOG" \
  "$SB_APP/Contents/MacOS/DeepSeek Harness" --user-data-dir="$SB_HOME/eud" \
  >>"$SANDBOX/app.log" 2>&1 &
APP_PID=$!

st="none"
for _ in $(seq 1 120); do
  sleep 1
  if [ -f "$LOG/app.log" ]; then
    if grep -q "鉴权失败" "$LOG/app.log" 2>/dev/null; then st="failed"; break; fi
    if grep -q "GUI 就绪" "$LOG/app.log" 2>/dev/null; then st="ok"; break; fi
  fi
done
if [ "$st" = "ok" ]; then
  ok "app 自己完成鉴权并进入界面（auth=token）"
elif [ "$st" = "failed" ]; then
  bad "app 鉴权失败"
  tail -6 "$LOG/app.log" 2>/dev/null | sed 's/^/      /'
else
  bad "120 秒内无鉴权结论"
  tail -6 "$LOG/app.log" 2>/dev/null | sed 's/^/      /'
fi

SEEDED="$SB_HOME/.dsh/profiles/web/package.json"
if [ -f "$SEEDED" ]; then
  nb=$(python3 -c "import json;print(len(json.load(open('$SEEDED'))['dsh']['profile']['bundles']))" 2>/dev/null)
  ok "首启已用内嵌种子初始化 ~/.dsh（${nb} 个 bundle）"
else
  bad "首启未初始化 ~/.dsh"
fi

# ---- 5. 只读卷未被改动 ------------------------------------------------------
if [ -d "$MNT/DeepSeek Harness.app" ] && [ -f "$MNT/DeepSeek Harness.app/Contents/Resources/app/main.js" ]; then
  ok "安装后只读卷内容完好"
else
  bad "只读卷内容异常"
fi

echo "════════════════════════════════════════"
echo "沙盒场景 C: 通过 $PASS 项 / 失败 $FAIL 项"
[ "$FAIL" -eq 0 ] && { echo "结论：真实 DMG 端到端 ✓"; exit 0; } || { echo "结论：未达标 ✗"; exit 1; }
