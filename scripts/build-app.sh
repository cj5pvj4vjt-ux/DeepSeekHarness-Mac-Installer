#!/bin/bash
# =============================================================================
# build-app.sh — 一键组装（更新种子 -> 自包含 runtime -> 重签 -> 校验）
#
# 用法：./build-app.sh "<原始 DeepSeek Harness.app>" "<输出目录>"
# 输出：<输出目录>/DeepSeek Harness.app
# =============================================================================
set -euo pipefail

SRC_APP="${1:?用法: $0 <原始 .app> <输出目录>}"
OUT_DIR="${2:?缺少输出目录}"
APP="$OUT_DIR/DeepSeek Harness.app"
HERE="$(cd "$(dirname "$0")" && pwd)"

[ -d "$SRC_APP" ] || { echo "错误: 找不到原始 app $SRC_APP"; exit 1; }
mkdir -p "$OUT_DIR"

echo "== 1/4 拷贝原始 app =="
rm -rf "$APP"
cp -R "$SRC_APP" "$APP"

echo "== 2/4 同步 profile 种子（插件全家桶）=="
"$HERE/sync-profile-seed.sh" "$APP"

echo "== 3/4 内嵌 agent presets（梁神模式 等）=="
if [ -d "$HOME/.dsh/.agent-presets" ]; then
  rm -rf "$APP/Contents/Resources/agent-presets-seed"
  mkdir -p "$APP/Contents/Resources/agent-presets-seed"
  for d in "$HOME/.dsh/.agent-presets"/*/; do
    [ -d "$d" ] || continue
    cp -R "$d" "$APP/Contents/Resources/agent-presets-seed/$(basename "$d")"
    echo "  已加入 preset: $(basename "$d")"
  done
fi

echo "== 4/4 自包含 runtime + 重签 =="
"$HERE/bundle-homebrew-deps.sh" "$APP"
xattr -cr "$APP" 2>/dev/null || true
codesign --force --deep --sign - "$APP" 2>/dev/null || true
echo ""
echo "完成 ✓ $APP"
echo "验证 node: $APP/Contents/Resources/runtime/bin/node --version"