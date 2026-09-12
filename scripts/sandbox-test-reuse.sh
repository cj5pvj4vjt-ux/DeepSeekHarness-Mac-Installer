#!/bin/bash
# =============================================================================
# sandbox-test-reuse.sh — 场景 B：端口已被「别的 dsh web 实例」占用
#
# 这正是 v0.2.0 在真实机器上卡死的场景：
#   - 用户自己（或别的工具）先在 3080 起了 dsh web；
#   - 封装 App 双击后探测到端口有服务，就不启动自己的；
#   - 但它没有那次会话的 token，于是永久停在 401 页面。
#
# v0.3.0 的预期行为分两种：
#   1) 本应用之前成功鉴权过（Electron 会话里有 30 天 cookie）
#      → 直接凭 cookie 复用，日志出现「HTTP 200」，且**不**出现「鉴权失败」
#   2) 没有 cookie → 提示用户是否「接管并重启服务」
#
# 本脚本自动验证 (1)；(2) 需要人工点对话框，脚本只检查它到达了该状态。
#
# 用法：./sandbox-test-reuse.sh "<DeepSeek Harness.app>" [序号]
# =============================================================================
set -uo pipefail

APP="${1:?用法: $0 <DeepSeek Harness.app> [序号]}"
IDX="${2:-1}"
PORT=$((39100 + IDX))
SANDBOX="/tmp/dsh-sandbox-reuse-$IDX"
SB_HOME="$SANDBOX/home"
SB_APP="$SB_HOME/Applications/DeepSeek Harness.app"
LOG="$SB_HOME/Library/Logs/DeepSeek Harness"

PASS=0; FAIL=0
ok()   { echo "  ✓ $*"; PASS=$((PASS + 1)); }
bad()  { echo "  ✗ $*"; FAIL=$((FAIL + 1)); }
info() { echo "    $*"; }

APPS=()
LAST_PID=""
cleanup() {
  if [ "${#APPS[@]}" -gt 0 ]; then
    for p in "${APPS[@]}"; do kill "$p" 2>/dev/null; done
  fi
  sleep 1
  local pids; pids="$(lsof -ti "tcp:$PORT" 2>/dev/null)"
  [ -n "$pids" ] && kill $pids 2>/dev/null
  return 0
}
trap cleanup EXIT

launch_app() {  # $1=日志文件（注意：macOS 自带 bash 3.2，不能用数组负索引）
  HOME="$SB_HOME" DSH_HOME="$SB_HOME/.dsh" DSH_PORT="$PORT" \
  DSH_NO_FULLSCREEN=1 DSH_LOG_DIR="$LOG" \
    "$SB_APP/Contents/MacOS/DeepSeek Harness" --user-data-dir="$SB_HOME/eud" \
    >>"$SANDBOX/$1" 2>&1 &
  LAST_PID=$!
  APPS+=("$LAST_PID")
  return 0
}

wait_http() {  # $1=期望状态（空格分隔可多个）  $2=次数
  local want="$1" n="${2:-60}" c
  for _ in $(seq 1 "$n"); do
    sleep 1
    c="$(curl -s -o /dev/null --max-time 4 -w '%{http_code}' "http://127.0.0.1:$PORT/" 2>/dev/null)"
    for w in $want; do [ "$c" = "$w" ] && { echo "$c"; return 0; }; done
  done
  echo "${c:-000}"; return 1
}

echo "════════ 沙盒场景 B：端口被占用（端口 ${PORT}）════════"
rm -rf "$SANDBOX"; mkdir -p "$SB_HOME/Applications"
cp -R "$APP" "$SB_APP" || { bad "拷贝 app 失败"; exit 1; }
ok "已准备沙盒 app：$SB_APP"

# ---- 第 1 步：正常首启一次，让它自己起服务并在会话里种下 cookie -------------
echo "[1] 首次启动（自己拉起服务 → 种下 cookie）"
launch_app first.log >/dev/null
st="none"
for _ in $(seq 1 90); do
  sleep 1
  if [ -f "$LOG/app.log" ]; then
    if grep -q "鉴权失败" "$LOG/app.log" 2>/dev/null; then st="failed"; break; fi
    if grep -q "GUI 就绪" "$LOG/app.log" 2>/dev/null; then st="ok"; break; fi
  fi
done
if [ "$st" = "ok" ]; then
  ok "首启完成鉴权并进入界面（auth=token）"
elif [ "$st" = "failed" ]; then
  bad "首启就鉴权失败（后续 cookie 复用无从谈起）"
  tail -5 "$LOG/app.log" 2>/dev/null | sed 's/^/      /'
else
  bad "首启 90 秒内无鉴权结论"
  tail -5 "$LOG/app.log" 2>/dev/null | sed 's/^/      /'
fi
# 等 Chromium 把 dsh-auth cookie 落进会话（要合并 WAL，有延迟，必须轮询）
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
[ "${nck:-0}" -ge 1 ] && ok "首启已种下 dsh-auth cookie（${nck} 条）" || bad "首启没有种下 dsh-auth cookie"

# 关掉 app（它会把子服务一起关掉），为「外部实例」腾出端口
for p in "${APPS[@]}"; do kill "$p" 2>/dev/null; done
APPS=()
sleep 4
pids="$(lsof -ti "tcp:$PORT" 2>/dev/null)"; [ -n "$pids" ] && kill $pids 2>/dev/null
sleep 2
[ -z "$(lsof -ti "tcp:$PORT" 2>/dev/null)" ] && ok "端口已腾空" || bad "端口未腾空"

# ---- 第 2 步：用内嵌运行时起一个「外部」dsh web（它会生成全新 token）--------
echo "[2] 起一个外部 dsh web 实例占用端口（模拟用户自己先跑了服务）"
HOME="$SB_HOME" DSH_HOME="$SB_HOME/.dsh" \
  "$SB_APP/Contents/Resources/runtime/bin/node" \
  "$SB_APP/Contents/Resources/runtime/dsh/lib/bin.js" web --port "$PORT" \
  >"$SANDBOX/foreign-web.log" 2>&1 &
APPS+=("$!")
code="$(wait_http "401" 60)"
[ "$code" = "401" ] && ok "外部实例已在监听（裸地址 401，符合预期）" || bad "外部实例未起来（HTTP ${code}）"
FOREIGN_TOKEN="$(grep -oE '[?&]token=[A-Za-z0-9._~-]+' "$SANDBOX/foreign-web.log" 2>/dev/null | tail -1 | cut -d= -f2)"
info "外部实例 token 已生成（本应用并不知道它）"

# ---- 第 3 步：再启动 app，应凭 cookie 直接复用 ------------------------------
echo "[3] 再次启动 app → 应凭 cookie 复用，而不是停在 401"
: > "$LOG/app.log"   # 清空日志便于判定本次行为
launch_app second.log >/dev/null
for _ in $(seq 1 60); do
  sleep 1
  grep -q "鉴权探测 → HTTP 200" "$LOG/app.log" 2>/dev/null && break
  grep -q "鉴权失败" "$LOG/app.log" 2>/dev/null && break
done
if grep -q "鉴权探测 → HTTP 200" "$LOG/app.log" 2>/dev/null; then
  ok "凭已有 cookie 通过鉴权（HTTP 200）"
else
  bad "未凭 cookie 通过鉴权"
  tail -6 "$LOG/app.log" 2>/dev/null | sed 's/^/      /'
fi
if grep -q "鉴权失败" "$LOG/app.log" 2>/dev/null; then
  bad "仍然走到了「鉴权失败」（不应该）"
else
  ok "未出现「鉴权失败」，无需用户介入"
fi
if grep -q "已有服务 → 直接复用" "$LOG/app.log" 2>/dev/null; then
  ok "识别出端口已有服务并复用（没有去杀别人的进程）"
else
  bad "未识别出复用场景"
fi
# app 进程应仍然存活（没有因为失败而退出）
alive=0
for p in "${APPS[@]}"; do kill -0 "$p" 2>/dev/null && alive=1; done
[ "$alive" = "1" ] && ok "app 进程存活（界面已加载，未卡死退出）" || bad "app 进程已退出"

# 外部实例应**未**被误杀
if lsof -ti "tcp:$PORT" >/dev/null 2>&1; then
  ok "端口上的服务仍在（未误杀外部实例）"
else
  bad "端口服务消失了（可能误杀了外部实例）"
fi

echo "════════════════════════════════════════"
echo "沙盒场景 B: 通过 $PASS 项 / 失败 $FAIL 项"
[ "$FAIL" -eq 0 ] && { echo "结论：端口被占用时的复用行为 ✓"; exit 0; } || { echo "结论：未达标 ✗"; exit 1; }
