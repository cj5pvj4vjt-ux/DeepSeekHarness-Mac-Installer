#!/bin/bash
# =============================================================================
# build-app.sh — 一键组装（源码覆盖 -> 种子 -> preset -> runtime -> 自包含 -> 重签 -> 校验）
#
# 用法：./build-app.sh "<原始 DeepSeek Harness.app>" "<输出目录>" [版本号]
# 环境变量：
#   DSH_RUNTIME_SRC   可选。用指定目录的 dsh 安装替换内嵌 runtime/dsh
#                     （例如 /opt/homebrew/lib/node_modules/@deepseek-ai/dsh）
#   APP_VERSION       可选。等价于第 3 个参数。
#
# 输出：<输出目录>/DeepSeek Harness.app
# =============================================================================
set -euo pipefail

SRC_APP="${1:?用法: $0 <原始 .app> <输出目录> [版本号]}"
OUT_DIR="${2:?缺少输出目录}"
VERSION="${3:-${APP_VERSION:-0.3.0}}"
APP="$OUT_DIR/DeepSeek Harness.app"
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
RES="$APP/Contents/Resources"

[ -d "$SRC_APP" ] || { echo "错误: 找不到原始 app $SRC_APP"; exit 1; }
[ -f "$REPO/app/main.js" ] || { echo "错误: 找不到仓库源码 $REPO/app/main.js"; exit 1; }
mkdir -p "$OUT_DIR"

echo "== 1/7 拷贝原始 app =="
rm -rf "$APP"
cp -R "$SRC_APP" "$APP"

echo "== 2/7 覆盖 Electron 主进程源码（以本仓库 app/ 为准）=="
rm -rf "$RES/app"
mkdir -p "$RES/app"
cp "$REPO/app/main.js" "$REPO/app/package.json" "$RES/app/"
# 写死版本号，保证「仓库里的源码」= 「App 里跑的源码」
python3 - "$RES/app/package.json" "$VERSION" <<'PY'
import json, sys
p, v = sys.argv[1], sys.argv[2]
d = json.load(open(p, encoding="utf-8"))
d["version"] = v
d["description"] = "DeepSeek Harness 桌面应用（自包含运行时 + 全家桶插件，分享版 %s）" % v
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
open(p, "a", encoding="utf-8").write("\n")
PY
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
                         -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist" 2>/dev/null || true
echo "  版本号 → $VERSION"

echo "== 3/7 同步 profile 种子（插件全家桶）=="
"$HERE/sync-profile-seed.sh" "$APP"

echo "== 4/7 内嵌 agent presets（梁神模式 等）=="
if [ -d "$HOME/.dsh/.agent-presets" ]; then
  rm -rf "$RES/agent-presets-seed"
  mkdir -p "$RES/agent-presets-seed"
  for d in "$HOME/.dsh/.agent-presets"/*/; do
    [ -d "$d" ] || continue
    cp -R "$d" "$RES/agent-presets-seed/$(basename "$d")"
    echo "  已加入 preset: $(basename "$d")"
  done
fi

echo "== 5/7 内嵌 dsh 运行时 =="
if [ -n "${DSH_RUNTIME_SRC:-}" ]; then
  [ -f "$DSH_RUNTIME_SRC/package.json" ] || { echo "错误: $DSH_RUNTIME_SRC 不是 dsh 安装目录"; exit 1; }
  rm -rf "$RES/runtime/dsh"
  mkdir -p "$RES/runtime/dsh"
  cp -R "$DSH_RUNTIME_SRC/." "$RES/runtime/dsh/"
  echo "  已替换 → $(python3 -c "import json;print(json.load(open('$RES/runtime/dsh/package.json'))['version'])")"
else
  echo "  保持原始 app 内的 runtime/dsh（未指定 DSH_RUNTIME_SRC）"
fi
echo "  node: $("$RES/runtime/bin/node" --version 2>/dev/null || echo 缺失)"

echo "== 6/7 自包含化：内嵌 Homebrew 依赖 + 重签 =="
"$HERE/bundle-homebrew-deps.sh" "$APP"
xattr -cr "$APP" 2>/dev/null || true
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "== 7/7 自检 =="
"$HERE/verify-selfcontained.sh" "$APP" || { echo "!! 自检未通过"; exit 1; }

echo ""
echo "完成 ✓ ${APP}（v${VERSION}）"
