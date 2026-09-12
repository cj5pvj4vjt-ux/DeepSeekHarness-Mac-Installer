#!/bin/bash
# =============================================================================
# sandbox-test.sh — 模拟「全新 Mac」端到端验收（不改动本机真实环境）
#
# 做法：给这次运行一个**全新的 HOME / DSH_HOME / Electron userData / 端口**，
#       然后用安装器装、启动、验证，全程不碰真实的 ~/.dsh 与真实端口。
#
# 用法：./sandbox-test.sh "<DeepSeek Harness.app>" ["<安装 DeepSeek Harness.app>"] [序号]
#   序号只用于生成独立的沙盒目录与端口，默认 1。
#
# 检查项：
#   A 安装器把 app 拷到沙盒的 ~/Applications
#   B 首启用内嵌种子初始化 ~/.dsh（含全部插件 bundle + patchReload）
#   C 由 app 自己拉起 dsh web，并从输出里抓到带 token 的地址
#   D 用该 token 访问 GUI 返回 200（即真正解决了 401）
#   E 真实 ~/.dsh 未被改动
#   F 二次启动：已有 ~/.dsh 时不覆盖用户配置
# =============================================================================
set -uo pipefail

APP="${1:?用法: $0 <DeepSeek Harness.app> [安装器.app] [序号]}"
INSTALLER_APP="${2:-}"
IDX="${3:-1}"
PORT=$((39000 + IDX))
SANDBOX="/tmp/dsh-sandbox-$IDX"
SB_HOME="$SANDBOX/home"
SB_APP="$SB_HOME/Applications/DeepSeek Harness.app"
LOG="$SB_HOME/Library/Logs/DeepSeek Harness"

PASS=0; FAIL=0
ok()   { echo "  ✓ $*"; PASS=$((PASS + 1)); }
bad()  { echo "  ✗ $*"; FAIL=$((FAIL + 1)); }
info() { echo "    $*"; }

cleanup() {
  [ -n "${APP_PID:-}" ] && kill "$APP_PID" 2>/dev/null
  sleep 1
  local pids
  pids="$(lsof -ti "tcp:$PORT" 2>/dev/null)"
  [ -n "$pids" ] && kill $pids 2>/dev/null
  return 0
}
trap cleanup EXIT

echo "════════ 沙盒测试 #${IDX}（端口 ${PORT}）════════"
echo "  沙盒: $SANDBOX"

# --- 真实环境指纹（用于 E 项对比）-------------------------------------------
REAL_DSH="$HOME/.dsh"
real_before=""
[ -d "$REAL_DSH" ] && real_before="$(find "$REAL_DSH" -maxdepth 1 -exec basename {} \; 2>/dev/null | sort | tr '\n' ' ')"

rm -rf "$SANDBOX"
mkdir -p "$SB_HOME"

# -------------------------------------------------------------------- A 安装
echo "[A] 还原 DMG 目录结构，并用安装器安装到沙盒"
if [ -n "$INSTALLER_APP" ] && [ -x "$INSTALLER_APP/Contents/MacOS/installer" ]; then
  # 安装器的 install.sh 用「自身位置 ../../..」推导源 app，
  # 所以必须像 DMG 那样把「安装器 + 待装 app」并排放在同一个目录里，
  # 否则它会拷到别处的旧版本（这正是本脚本第一版踩过的坑）。
  STAGE="$SANDBOX/stage"
  rm -rf "$STAGE"; mkdir -p "$STAGE"
  cp -R "$INSTALLER_APP" "$STAGE/"
  cp -R "$APP" "$STAGE/DeepSeek Harness.app"
  ver="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
        "$STAGE/DeepSeek Harness.app/Contents/Info.plist" 2>/dev/null)"
  info "已搭好 DMG 舞台（待装 app 版本 ${ver}）"
  HOME="$SB_HOME" DSH_DEST_ROOT="$SB_HOME/Applications" DSH_NO_LAUNCH=1 \
    bash "$STAGE/安装 DeepSeek Harness.app/Contents/MacOS/installer"
  if [ -d "$SB_APP" ]; then
    ok "安装器已把 app 拷到 $SB_APP"
    iver="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
           "$SB_APP/Contents/Info.plist" 2>/dev/null)"
    [ "$iver" = "$ver" ] && ok "安装出来的版本与舞台一致（${iver}）" || bad "版本不一致：舞台 $ver → 装出 $iver"
  else
    bad "安装器未产出 app"
  fi
  rm -rf "$STAGE"
else
  mkdir -p "$SB_HOME/Applications"
  cp -R "$APP" "$SB_APP" 2>/dev/null
  if [ -d "$SB_APP" ]; then ok "已直接拷贝 app（未提供安装器）"; else bad "拷贝失败"; fi
fi

# ------------------------------------------------------- B/C/D 启动并验证
echo "[B/C/D] 全新 HOME 首启（自己拉起 dsh web + 抓 token + 加载 GUI）"
HOME="$SB_HOME" DSH_HOME="$SB_HOME/.dsh" DSH_PORT="$PORT" DSH_NO_FULLSCREEN=1 DSH_LOG_DIR="$LOG" \
  "$SB_APP/Contents/MacOS/DeepSeek Harness" --user-data-dir="$SB_HOME/eud" \
  >"$SANDBOX/app-stdout.log" 2>&1 &
APP_PID=$!
info "app pid=${APP_PID}，等待服务与鉴权（最多 120 秒）"

authed=0          # curl 侧：token 地址可达
app_state="none"  # app 侧：自己有没有真的完成鉴权（这才是关键判据）
for i in $(seq 1 120); do
  sleep 1
  # C：抓 token
  if [ -z "${TOKEN_URL:-}" ] && [ -f "$LOG/app-spawned-web.log" ]; then
    TOKEN_URL="$(grep -oE 'https?://[^[:space:]]*[?&]token=[A-Za-z0-9._~-]+' "$LOG/app-spawned-web.log" 2>/dev/null | tail -1)"
  fi
  # D：以 app 自己的结局为准 —— 出现「鉴权失败」或「GUI 就绪 …auth=」即定论
  if [ -f "$LOG/app.log" ]; then
    if grep -q "鉴权失败" "$LOG/app.log" 2>/dev/null; then app_state="failed"; break; fi
    if grep -q "GUI 就绪" "$LOG/app.log" 2>/dev/null; then app_state="ok"; break; fi
  fi
done

if [ -n "${TOKEN_URL:-}" ]; then
  ok "app 从服务输出里抓到了带 token 的地址"
else
  bad "没抓到 token（app-spawned-web.log 里无 token 行）"
fi

# 用 curl 独立复核 token 地址本身可达（curl 不跟随重定向，会看到 303）
if [ -n "${TOKEN_URL:-}" ]; then
  code="$(curl -s -o /dev/null --max-time 5 -w '%{http_code}' "$TOKEN_URL" 2>/dev/null)"
  if [ "$code" = "200" ] || [ "$code" = "303" ]; then
    authed=1
    ok "带 token 的地址本身可达（HTTP ${code}）"
  fi
fi

# 关键判据：app 自己必须完成鉴权并进入界面。
# 早期版本的测试只验了 curl，结果掩盖了「net 跟随重定向 → 401 → 卡在对话框」的真 bug。
if [ "$app_state" = "ok" ]; then
  if grep -q "auth=token" "$LOG/app.log" 2>/dev/null; then
    ok "app 自己完成鉴权并进入界面（auth=token）"
  else
    ok "app 自己完成鉴权并进入界面"
  fi
elif [ "$app_state" = "failed" ]; then
  bad "app 自己鉴权失败（日志出现「鉴权失败」）—— 这正是 v0.2.0 卡 401 的症状"
  tail -6 "$LOG/app.log" 2>/dev/null | sed 's/^/      /'
else
  bad "120 秒内未见 app 的鉴权结论"
  tail -6 "$LOG/app.log" 2>/dev/null | sed 's/^/      /'
fi

# cookie 是否落进 Electron 会话（决定二次启动能否免 token 直接复用）。
# Chromium 写 cookie 库有延迟（且要先合并 WAL），所以这里轮询等待，不能只查一次。
CK="$SB_HOME/eud/Cookies"
nck=0
for _ in $(seq 1 30); do
  sleep 1
  [ -f "$CK" ] || continue
  rm -f "$SANDBOX/ck.db" "$SANDBOX/ck.db-wal" 2>/dev/null
  cp "$CK" "$SANDBOX/ck.db" 2>/dev/null
  [ -f "$CK-wal" ] && cp "$CK-wal" "$SANDBOX/ck.db-wal" 2>/dev/null
  nck="$(sqlite3 "$SANDBOX/ck.db" "select count(*) from cookies where name like 'dsh-auth%';" 2>/dev/null)"
  [ "${nck:-0}" -ge 1 ] && break
done
if [ "${nck:-0}" -ge 1 ]; then
  ok "已种下 ${nck} 条 dsh-auth cookie（30 天内可免 token 复用）"
elif [ -f "$CK" ]; then
  bad "会话里没有 dsh-auth cookie（已等待 30 秒）"
else
  bad "未找到 Electron cookie 库"
fi

# B：种子是否正确落盘
SEEDED="$SB_HOME/.dsh/profiles/web/package.json"
if [ -f "$SEEDED" ]; then
  nb=$(python3 -c "import json;print(len(json.load(open('$SEEDED'))['dsh']['profile']['bundles']))" 2>/dev/null)
  pr=$(python3 -c "import json;d=json.load(open('$SEEDED'))['dsh']['profile'];print(d.get('patchReload','缺失'))" 2>/dev/null)
  ok "首启已用内嵌种子初始化 ~/.dsh（$nb 个 bundle，patchReload=${pr}）"
  [ "${nb:-0}" -ge 10 ] || bad "bundle 数量异常（${nb}）"
  [ "$pr" != "缺失" ] || bad "种子缺 patchReload（0.1.5+ 会重置 profile）"
  if [ -d "$SB_HOME/.dsh/profiles/web/node_modules" ]; then
    ok "node_modules 已随种子落地"
  else
    bad "node_modules 缺失"
  fi
else
  bad "首启未初始化 ~/.dsh/profiles/web"
fi
[ -f "$SB_HOME/.dsh/settings.yaml" ] && ok "默认 settings.yaml 已生成" || bad "settings.yaml 未生成"

# -------------------------------------------------------------------- E 隔离
real_after=""
[ -d "$REAL_DSH" ] && real_after="$(find "$REAL_DSH" -maxdepth 1 -exec basename {} \; 2>/dev/null | sort | tr '\n' ' ')"
if [ "$real_before" = "$real_after" ]; then ok "真实 ~/.dsh 未被改动"; else bad "真实 ~/.dsh 被改动了！"; fi

# -------------------------------------------------------------------- F 二启
echo "[F] 二次启动（已有 ~/.dsh）"
kill "$APP_PID" 2>/dev/null; sleep 3
pids="$(lsof -ti "tcp:$PORT" 2>/dev/null)"; [ -n "$pids" ] && kill $pids 2>/dev/null; sleep 2
# 放一个哨兵，验证二启不会覆盖用户配置
echo "sentinel-$(date +%s)" > "$SB_HOME/.dsh/profiles/web/USER-SENTINEL.txt"
HOME="$SB_HOME" DSH_HOME="$SB_HOME/.dsh" DSH_PORT="$PORT" DSH_NO_FULLSCREEN=1 DSH_LOG_DIR="$LOG" \
  "$SB_APP/Contents/MacOS/DeepSeek Harness" --user-data-dir="$SB_HOME/eud" \
  >>"$SANDBOX/app-stdout.log" 2>&1 &
APP_PID=$!
for i in $(seq 1 90); do
  sleep 1
  c="$(curl -s -o /dev/null --max-time 4 -w '%{http_code}' "http://127.0.0.1:$PORT/" 2>/dev/null)"
  [ "$c" = "200" ] || [ "$c" = "401" ] || [ "$c" = "303" ] && break
done
if [ -f "$SB_HOME/.dsh/profiles/web/USER-SENTINEL.txt" ]; then
  ok "二次启动保留了用户文件（未重置 profile）"
else
  bad "二次启动把用户文件清掉了（profile 被重置）"
fi
nb2=$(python3 -c "import json;print(len(json.load(open('$SEEDED'))['dsh']['profile']['bundles']))" 2>/dev/null)
[ "${nb2:-0}" -ge 10 ] && ok "二次启动后 bundle 数仍为 $nb2" || bad "二次启动后 bundle 数变成 $nb2"

kill "$APP_PID" 2>/dev/null; sleep 2

# -------------------------------------------------------------------- 汇总
echo "════════════════════════════════════════"
echo "沙盒测试 #$IDX: 通过 $PASS 项 / 失败 $FAIL 项"
[ "$FAIL" -eq 0 ] && { echo "结论：全新机器场景 ✓"; exit 0; } || { echo "结论：未达标 ✗"; exit 1; }
