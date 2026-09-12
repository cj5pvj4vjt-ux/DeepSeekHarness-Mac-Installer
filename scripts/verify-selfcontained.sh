#!/bin/bash
# =============================================================================
# verify-selfcontained.sh — 发布前自检：确认 .app 在「全新 Mac」上能独立运行
#
# 用法：./verify-selfcontained.sh "<path/to/DeepSeek Harness.app>"
# 退出码：0 = 全部通过；1 = 有阻断性问题
#
# 覆盖 7 类检查（v0.2.0 的教训 + v0.3.0 新增）：
#   1. 关键文件是否齐全
#   2. 符号链接是否只指向 app 内部（绝对链接会在别人机器上断掉）
#   3. node 与内嵌 dylib 是否还有 /opt/homebrew 绝对依赖
#   4. runtime/dsh 里的原生模块（*.node）是否还有 Homebrew 依赖
#   5. 种子配置里是否残留 /Users/<他人> 之类的绝对路径
#   6. 种子是否混入隐私数据（凭证 / 会话 / 日志）
#   7. 种子是否又被塞进嵌套的重复 profile 目录（0.1.0 的 489MB 事故）
# =============================================================================
set -uo pipefail

APP="${1:?用法: $0 <DeepSeek Harness.app>}"
RES="$APP/Contents/Resources"
FAIL=0
warn() { echo "  ⚠️  $*"; }
bad()  { echo "  ✗ $*"; FAIL=$((FAIL + 1)); }
ok()   { echo "  ✓ $*"; }

echo "════════ 自包含自检: $(basename "$APP") ════════"

# ---------------------------------------------------------------- 1. 关键文件
echo "[1/7] 关键文件"
for f in "Contents/Resources/app/main.js" \
         "Contents/Resources/app/package.json" \
         "Contents/Resources/runtime/bin/node" \
         "Contents/Resources/runtime/dsh/lib/bin.js" \
         "Contents/Resources/runtime/dsh/package.json" \
         "Contents/Resources/profile-seed-web/package.json" \
         "Contents/Resources/agent-presets-seed" \
         "Contents/MacOS/DeepSeek Harness"; do
  if [ -e "$APP/$f" ]; then ok "$f"; else bad "缺失: $f"; fi
done

# ------------------------------------------------------- 2. 越界符号链接
echo "[2/7] 符号链接是否越出 app 之外"
outside=0
for root in "$RES/profile-seed-web" "$RES/runtime" "$RES/app"; do
  [ -d "$root" ] || continue
  while IFS= read -r link; do
    tgt="$(readlink "$link")"
    case "$tgt" in
      /*) bad "绝对链接: ${link#$APP/} -> $tgt"; outside=$((outside + 1)) ;;
      *)  # 相对链接也不能指到 app 外面
          resolved="$(cd "$(dirname "$link")" 2>/dev/null && cd "$(dirname "$tgt")" 2>/dev/null && pwd)"
          case "$resolved" in
            "$APP"/*) ;;
            "") ;;
            *) warn "相对链接可能越界: ${link#$APP/} -> $tgt" ;;
          esac
          ;;
    esac
  done < <(find "$root" -type l 2>/dev/null)
done
[ "$outside" -eq 0 ] && ok "没有指向 app 外部的绝对符号链接"

# ------------------------------------------------- 3. node / lib 的 Homebrew
# 检查一个 Mach-O 的所有 @ 依赖是否都能在 app 内解析到真实文件（全新机器的真正判据）
check_macho_deps() {
  local f="$1" libdir="$2" bindir="$3" label="$4"
  local missing=0 dep p
  while IFS= read -r dep; do
    [ -n "$dep" ] || continue
    case "$dep" in
      @loader_path/../lib/*) p="$libdir/$(basename "$dep")" ;;
      @loader_path/*)        p="$bindir/$(basename "$dep")" ;;
      @rpath/*)              p="$libdir/$(basename "$dep")" ;;
      *) continue ;;
    esac
    if [ ! -e "$p" ]; then bad "$label 依赖无法解析: $dep"; missing=$((missing + 1)); fi
  done < <(otool -L "$f" 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -E "^@")
  return $missing
}

echo "[3/7] node 与 runtime/lib 的 Homebrew 依赖"
NODE="$RES/runtime/bin/node"
LIBDIR="$RES/runtime/lib"
if [ -x "$NODE" ]; then
  n=$(otool -L "$NODE" 2>/dev/null | grep -c "/opt/homebrew")
  [ "$n" -eq 0 ] && ok "bin/node 无 /opt/homebrew 引用" || bad "bin/node 仍有 $n 处 /opt/homebrew"
  if otool -L "$NODE" 2>/dev/null | grep -q "@rpath/libnode"; then
    if otool -l "$NODE" 2>/dev/null | grep -A2 LC_RPATH | grep -q "@loader_path/../lib"; then
      ok "bin/node 经 @rpath → @loader_path/../lib 解析 libnode"
    else
      bad "bin/node 引用 @rpath/libnode 但缺少 @loader_path/../lib"
    fi
  fi
  if check_macho_deps "$NODE" "$LIBDIR" "$RES/runtime/bin" "bin/node"; then
    ok "bin/node 的全部内嵌依赖均可解析"
  fi
else
  bad "找不到可执行的 runtime/bin/node"
fi
if [ -d "$LIBDIR" ]; then
  cnt=0; badlib=0; unres=0
  for f in "$LIBDIR"/*.dylib; do
    [ -e "$f" ] || continue
    cnt=$((cnt + 1))
    c=$(otool -L "$f" 2>/dev/null | grep -c "/opt/homebrew")
    [ "$c" -gt 0 ] && { bad "$(basename "$f") 仍有 $c 处 /opt/homebrew"; badlib=$((badlib + 1)); }
    check_macho_deps "$f" "$LIBDIR" "$LIBDIR" "$(basename "$f")" || unres=$((unres + 1))
  done
  [ "$badlib" -eq 0 ] && ok "runtime/lib 共 $cnt 个 dylib，全部无绝对路径依赖"
  [ "$unres" -eq 0 ] && ok "runtime/lib 内部依赖全部可解析"
  # 说明：libcrypto / libnode 等二进制里**内嵌字符串**可能仍出现 /opt/homebrew
  # （OpenSSL 的 engines-3 目录、node 的构建期路径等）。那只是编译期常量，
  # 不在 dyld 的加载依赖里，启动时不会被访问 —— 上面用 otool -L 判定即可，
  # 不要用 grep 扫二进制，否则会误报成「依赖泄漏」。
  emb="$(for f in "$LIBDIR"/*.dylib; do
            [ -e "$f" ] || continue
            otool -L "$f" 2>/dev/null | tail -n +2 | grep -q "/opt/homebrew" || continue
            basename "$f"
          done | wc -l | tr -d ' ')"
  [ "$emb" -eq 0 ] && ok "无 dylib 通过加载命令引用 Homebrew（内嵌字符串不算）"
fi

# ------------------------------------------- 4. runtime/dsh 原生模块 (*.node)
echo "[4/7] runtime/dsh 原生模块"
native_list="$(find "$RES/runtime/dsh" -name "*.node" -type f 2>/dev/null)"
native_cnt=$(printf '%s\n' "$native_list" | grep -c . || true)
badnative=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  c=$(otool -L "$f" 2>/dev/null | grep -c "/opt/homebrew")
  [ "$c" -gt 0 ] && { bad "$(basename "$f") 仍有 $c 处 /opt/homebrew"; badnative=$((badnative + 1)); }
done <<< "$native_list"
[ "$badnative" -eq 0 ] && ok "$native_cnt 个原生模块无 Homebrew 依赖"

# ------------------------------------------------- 5. 种子里的绝对路径残留
echo "[5/7] 种子配置中的绝对路径"
abs=0
for f in "$RES/profile-seed-web/package.json" \
         "$RES/profile-seed-web/pnpm-workspace.yaml" \
         "$RES/profile-seed-web/cordis.yml" \
         "$RES/profile-seed-web/cordis.patch.yml"; do
  [ -f "$f" ] || continue
  if grep -qE "/Users/[A-Za-z0-9._-]+|/opt/homebrew" "$f" 2>/dev/null; then
    bad "$(basename "$f") 含绝对路径"
    grep -nE "/Users/[A-Za-z0-9._-]+|/opt/homebrew" "$f" 2>/dev/null | head -3 | sed 's/^/      /'
    abs=$((abs + 1))
  fi
done
[ "$abs" -eq 0 ] && ok "种子配置文件无本机绝对路径"

# ------------------------------------------------------------ 6. 隐私数据
echo "[6/7] 种子是否混入隐私"
priv=0
for f in ".credentials.yaml" ".credentials.yml" "settings.yaml" "pet.json" "skin-center-active.json"; do
  if [ -e "$RES/profile-seed-web/$f" ]; then bad "种子含 $f"; priv=$((priv + 1)); fi
done
if [ -d "$RES/profile-seed-web/sessions" ] && [ -n "$(ls -A "$RES/profile-seed-web/sessions" 2>/dev/null)" ]; then
  bad "种子含会话记录 sessions/"; priv=$((priv + 1))
fi
# 常见 key 形态的探测（sk- / API key 字段）
if grep -rqE "sk-[A-Za-z0-9]{16,}|apiKey[\"']?\s*[:=]\s*[\"'][A-Za-z0-9_-]{16,}" \
     "$RES/profile-seed-web/package.json" "$RES/profile-seed-web/cordis.patch.yml" 2>/dev/null; then
  bad "种子配置里疑似存在 API Key"; priv=$((priv + 1))
fi
[ "$priv" -eq 0 ] && ok "未发现凭证 / 会话 / 密钥残留"

# ------------------------------------------------------- 7. 嵌套重复目录
echo "[7/7] 体积与结构"
if [ -d "$RES/profile-seed-web/profile-seed-web" ]; then
  bad "存在嵌套重复目录 profile-seed-web/profile-seed-web（0.1.0 的 489MB 事故）"
else
  ok "无嵌套重复 profile 目录"
fi
seed_size=$(du -sm "$RES/profile-seed-web" 2>/dev/null | cut -f1)
rt_size=$(du -sm "$RES/runtime" 2>/dev/null | cut -f1)
app_size=$(du -sm "$APP" 2>/dev/null | cut -f1)
echo "      种子 ${seed_size}MB / runtime ${rt_size}MB / app 合计 ${app_size}MB"
if [ "${app_size:-0}" -gt 1500 ]; then warn "app 体积偏大（${app_size}MB）"; fi

# ------------------------------------------------------------------- 汇总
echo "════════════════════════════════════════"
if [ "$FAIL" -eq 0 ]; then
  echo "自检通过 ✓ 可用于「全新 Mac」分发"
  exit 0
else
  echo "自检失败 ✗ 共 $FAIL 项阻断问题，禁止分发"
  exit 1
fi
